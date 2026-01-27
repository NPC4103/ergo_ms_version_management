<template>
  <div class="card kpi-card shadow-sm">
    <div class="card-body">
      <div class="d-flex justify-content-between align-items-center mb-3">
        <h5 class="card-title mb-0">Дашборд метрик репозитория</h5>
        <span class="kpi-period text-muted small">
          Период: {{ periodLabel }}
        </span>
      </div>

      <div class="kpi-grid">
        <div class="kpi-item">
          <div class="kpi-label">Всего коммитов</div>
          <div class="kpi-value">{{ totalCommits }}</div>
          <div class="kpi-subtext text-muted">
            {{ avgCommitsPerDay }} в день в среднем
          </div>
        </div>

        <div class="kpi-item">
          <div class="kpi-label">Средний размер diff</div>
          <div class="kpi-value">
            {{ avgDiffSizeFormatted }}
          </div>
          <div class="kpi-subtext text-muted">
            по числу изменённых строк
          </div>
        </div>

        <div class="kpi-item">
          <div class="kpi-label">Активных дней</div>
          <div class="kpi-value">{{ activeDays }}</div>
          <div class="kpi-subtext text-muted">
            с минимум одним коммитом
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';

const props = defineProps({
  commits: {
    type: Array,
    required: true,
  },
  period: {
    type: String,
    default: '30',
  },
});

const periodLabel = computed(() => {
  const p = parseInt(props.period || '30', 10) || 30;
  if (p === 7) return 'последние 7 дней';
  if (p === 30) return 'последние 30 дней';
  if (p === 90) return 'последние 90 дней';
  if (p === 365) return 'последний год';
  return `последние ${p} дней`;
});

const totalCommits = computed(() => props.commits?.length || 0);

const activeDays = computed(() => {
  if (!props.commits || !props.commits.length) return 0;
  const set = new Set(
    props.commits
      .filter((c) => c && c.created_at)
      .map((c) => c.created_at.slice(0, 10)),
  );
  return set.size;
});

const avgCommitsPerDay = computed(() => {
  const days = Math.max(parseInt(props.period || '30', 10) || 30, 1);
  const avg = (totalCommits.value || 0) / days;
  if (!Number.isFinite(avg)) return '0';
  return avg.toFixed(avg >= 1 ? 1 : 2);
});

const avgDiffSize = computed(() => {
  if (!props.commits || !props.commits.length) return 0;

  let sum = 0;
  let count = 0;

  for (const c of props.commits) {
    if (!c) continue;
    let diff = 0;

    if (typeof c.diff_size === 'number' && !Number.isNaN(c.diff_size)) {
      diff = c.diff_size;
    } else if (typeof c.files_count === 'number') {
      diff = c.files_count * 5;
    }

    if (diff > 0) {
      sum += diff;
      count += 1;
    }
  }

  if (count === 0) return 0;
  return sum / count;
});

const avgDiffSizeFormatted = computed(() => {
  const value = avgDiffSize.value || 0;
  if (!Number.isFinite(value) || value <= 0) return 'нет данных';

  if (value < 10) return `${value.toFixed(1)} строк`;
  if (value < 100) return `${Math.round(value)} строк`;
  return `${Math.round(value)} строк`;
});
</script>

<style scoped>
.kpi-card {
  border: none;
  background: var(--bs-card-bg);
  border-radius: 10px;
  transition: all 0.2s;
  border-left: 4px solid #ef4444;
}

.kpi-card:hover {
  box-shadow: 0 4px 16px rgba(0, 0, 0, 0.18) !important;
}

.card-title {
  font-weight: 600;
  color: var(--bs-body-color);
}

.kpi-period {
  font-size: 0.85rem;
}

.kpi-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 16px;
  margin-top: 8px;
}

.kpi-item {
  padding: 12px 14px;
  border-radius: 8px;
  background: var(--bs-body-bg);
  border: 1px solid var(--bs-border-color);
}

.kpi-label {
  font-size: 0.8rem;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--bs-body-color);
  opacity: 0.75;
  margin-bottom: 4px;
}

.kpi-value {
  font-size: 1.6rem;
  font-weight: 700;
  color: #ef4444;
  line-height: 1.1;
}

.kpi-subtext {
  font-size: 0.8rem;
  margin-top: 4px;
}

@media (max-width: 992px) {
  .kpi-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 576px) {
  .kpi-grid {
    grid-template-columns: 1fr;
  }

  .kpi-card {
    padding: 0;
  }
}
</style>

