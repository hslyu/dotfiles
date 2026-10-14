import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export const SEED_LINEAGE = ['gpt-6.1-sol', 'gpt-6-astra'];
export const EFFORTS = ['max', 'xhigh'];
export const stageKey = stage => `${stage.model}:${stage.effort}`;
export const sameStage = (a, b) => Boolean(a && b && stageKey(a) === stageKey(b));
export const isCapacityError = error => error?.codexErrorInfo === 'serverOverloaded'
  || (typeof error?.message === 'string'
    && /^Selected model is at capacity\.(?:\s|$)/i.test(error.message.trim()));

function supports(model, effort) {
  return model?.supportedReasoningEfforts?.some(option => option.reasoningEffort === effort) ?? false;
}

function eligible(model) {
  return model && !model.hidden && !model.modelSpecialty
    && !/(?:^|-)(?:luna|mini|nano|spark|reserve|image|audio|realtime|cyber)(?:-|$)/i.test(model.model)
    && EFFORTS.some(effort => supports(model, effort));
}

// isDefault and upgrade are recommendations, not benchmark/SOTA scores.
// Persist history so the previous primary remains second after a new recommendation.
export class RoutingPolicy {
  constructor(metadata = new Map(), { path = null, identity = null, lineage = SEED_LINEAGE } = {}) {
    this.metadata = metadata;
    this.path = path;
    this.identity = identity;
    this.lineage = [...lineage];
    if (path) {
      try {
        const saved = JSON.parse(readFileSync(path, 'utf8'));
        if (saved.version === 2 && saved.identity === identity && Array.isArray(saved.lineage)
            && saved.lineage.length && saved.lineage.every(model => typeof model === 'string')) {
          this.lineage = [...new Set(saved.lineage)];
        }
      } catch { /* First launch or an incomplete old file: use the requested seed. */ }
    }
    this.update(metadata);
  }

  update(metadata) {
    if (this.path) {
      try {
        const saved = JSON.parse(readFileSync(this.path, 'utf8'));
        if (saved.version === 2 && saved.identity === this.identity && Array.isArray(saved.lineage)
            && saved.lineage.length && saved.lineage.every(model => typeof model === 'string')) {
          this.lineage = [...new Set(saved.lineage)];
        }
      } catch { /* No persisted history yet. */ }
    }
    this.metadata = metadata;
    const primary = metadata.get(this.lineage[0]);
    const target = primary?.upgradeInfo?.model ?? primary?.upgrade;
    let recommended = eligible(metadata.get(target)) ? target : null;
    if (!recommended) {
      recommended = [...metadata.values()].find(model => model.isDefault && eligible(model))?.model;
    }
    // An old fallback briefly becoming the default must not cause oscillation.
    if (recommended && !this.lineage.includes(recommended)) {
      this.lineage.unshift(recommended);
      this.save();
    } else if (this.path) this.save();
  }

  save() {
    if (!this.path) return;
    mkdirSync(dirname(this.path), { recursive: true });
    const temporary = `${this.path}.${process.pid}.tmp`;
    writeFileSync(temporary, JSON.stringify({ version: 2, identity: this.identity, lineage: this.lineage }, null, 2) + '\n', { mode: 0o600 });
    renameSync(temporary, this.path);
  }

  stages() {
    const models = this.lineage.filter(name => this.metadata.size === 0 || eligible(this.metadata.get(name))).slice(0, 2);
    return EFFORTS.flatMap(effort => models.filter(model => this.metadata.size === 0 || supports(this.metadata.get(model), effort))
      .map(model => ({ model, effort })));
  }
}

export function routeParams(params, stage) {
  const routed = structuredClone(params);
  routed.model = stage.model;
  routed.effort = stage.effort;
  if (routed.collaborationMode?.settings) {
    routed.collaborationMode.settings.model = stage.model;
    routed.collaborationMode.settings.reasoning_effort = stage.effort;
  }
  return routed;
}
