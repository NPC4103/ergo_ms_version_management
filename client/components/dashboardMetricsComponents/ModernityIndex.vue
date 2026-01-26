<template>
  <div class="card metric-card shadow-sm">
    <div class="card-body">
      <h6 class="card-title mb-3">Индекс современности (MTI)</h6>
      <p class="text-muted small mb-4">Взвешенная оценка актуальности используемых технологий</p>
      
      <div class="metric-display mb-4">
        <div class="metric-value">{{ mtiValue }}</div>
        <div class="metric-label">уровень современности (0-100)</div>
      </div>

      <div class="mti-card">
        <div class="mti-badge" :class="mtiClass">{{ mtiLabel }}</div>
        <p class="mti-description">{{ mtiDescription }}</p>

        <div v-if="Object.keys(weightedScores).length > 0" class="mti-details">
          <div v-for="(score, lang) in weightedScores" :key="lang" class="detail-row">
            <span class="detail-label">{{ lang }}</span>
            <span class="detail-value">{{ (score * 100).toFixed(1) }}%</span>
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
    required: true
  },
  period: {
    type: String,
    default: '30'
  }
});

const LANGUAGE_WEIGHTS = {
  'TypeScript': 1.0,
  'Python': 0.9,
  'C#': 0.9,
  'Rust': 0.95,
  'Go': 0.85,
  'Kotlin': 0.85,
  'Swift': 0.8,
  'Java': 0.8,
  'Ruby': 0.7,
  'JavaScript': 0.6,
  'PHP': 0.5,
  'Other': 0.3
};

const LANGUAGE_MAP = {
  '.js': 'JavaScript',
  '.ts': 'TypeScript',
  '.py': 'Python',
  '.cs': 'C#',
  '.cpp': 'C++',
  '.c': 'C',
  '.java': 'Java',
  '.go': 'Go',
  '.rs': 'Rust',
  '.php': 'PHP',
  '.rb': 'Ruby',
  '.swift': 'Swift',
  '.kt': 'Kotlin',
  '.jsx': 'JavaScript',
  '.tsx': 'TypeScript',
  '.vue': 'Vue',
  '.html': 'HTML',
  '.css': 'CSS'
};

const extractExtensions = (text) => {
  if (!text) return [];
  const matches = text.match(/\.\w+/g) || [];
  return [...new Set(matches)];
};

// Расчёт TSD (используется для MTI)
const calculateTSD = () => {
  const langCount = {};
  let totalFiles = 0;

  for (const commit of props.commits) {
    const exts = extractExtensions(commit.message);

    if (exts.length === 0) continue;

    for (const ext of exts) {
      const lang = LANGUAGE_MAP[ext.toLowerCase()] || 'Other';
      langCount[lang] = (langCount[lang] || 0) + 1;
      totalFiles++;
    }
  }

  if (totalFiles === 0) return [];

  return Object.entries(langCount)
    .map(([name, count]) => ({
      name,
      percent: parseFloat(((count / totalFiles) * 100).toFixed(1))
    }))
    .sort((a, b) => b.percent - a.percent);
};

// Расчёт MTI на основе TSD
const calculateMTI = (tsd) => {
  if (tsd.length === 0) return 0;

  let mti = 0;
  
  for (const lang of tsd) {
    const weight = LANGUAGE_WEIGHTS[lang.name] || 0.3;
    mti += (lang.percent / 100) * weight;
  }

  return Math.min(1, mti);
};

const tsd = computed(() => calculateTSD());
const mtiResult = computed(() => calculateMTI(tsd.value));

const mtiValue = computed(() => {
  return (mtiResult.value * 100).toFixed(0);
});

const mtiClass = computed(() => {
  const mti = mtiResult.value;
  if (mti > 0.8) return 'badge-advanced';
  if (mti > 0.65) return 'badge-modern';
  if (mti > 0.4) return 'badge-mixed';
  return 'badge-legacy';
});

const mtiLabel = computed(() => {
  const mti = mtiResult.value;
  if (mti > 0.8) return 'Передовой';
  if (mti > 0.65) return 'Современный';
  if (mti > 0.4) return 'Смешанный';
  return 'Устаревший';
});

const mtiDescription = computed(() => {
  const mti = mtiResult.value;
  if (mti > 0.8) {
    return 'Стек соответствует передовым инженерным практикам с использованием современных и прогрессивных технологий.';
  } else if (mti > 0.65) {
    return 'Актуальный технологический стек с хорошей поддержкой и соответствием современным стандартам.';
  } else if (mti > 0.4) {
    return 'Смешанный стек с элементами как новых, так и устаревших технологий. Возможна модернизация.';
  } else {
    return 'Стек содержит преимущественно устаревшие технологии. Рекомендуется постепенная модернизация.';
  }
});

const weightedScores = computed(() => {
  const scores = {};
  for (const lang of tsd.value) {
    const weight = LANGUAGE_WEIGHTS[lang.name] || 0.3;
    scores[lang.name] = (lang.percent / 100) * weight;
  }
  return scores;
});
</script>

<style scoped>
.metric-card {
  border: none;
  background: var(--bs-card-bg);
  border-radius: 8px;
  transition: all 0.2s;
  border-left: 4px solid #10b981;
}

.metric-card:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15) !important;
}

.card-title {
  font-weight: 600;
  color: var(--bs-body-color);
}

.metric-display {
  text-align: center;
  padding: 20px;
  background: var(--bs-tertiary-bg);
  border-radius: 8px;
}

.metric-value {
  font-size: 2.5rem;
  font-weight: 700;
  color: #10b981;
  line-height: 1;
}

.metric-label {
  font-size: 0.85rem;
  color: var(--bs-body-color);
  opacity: 0.7;
  margin-top: 8px;
  display: block;
}

.mti-card {
  background: var(--bs-tertiary-bg);
  border: 1px solid var(--bs-border-color);
  border-radius: 8px;
  padding: 16px;
}

.mti-badge {
  display: inline-block;
  padding: 6px 12px;
  border-radius: 4px;
  font-weight: 600;
  font-size: 0.85rem;
  margin-bottom: 12px;
}

.badge-advanced {
  background: #10b981;
  color: white;
}

.badge-modern {
  background: #3b82f6;
  color: white;
}

.badge-mixed {
  background: #f59e0b;
  color: white;
}

.badge-legacy {
  background: #ef4444;
  color: white;
}

.mti-description {
  font-size: 0.9rem;
  color: var(--bs-body-color);
  margin-bottom: 12px;
  line-height: 1.5;
}

.mti-details {
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding-top: 12px;
  border-top: 1px solid var(--bs-border-color);
}

.detail-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 0.85rem;
}

.detail-label {
  color: var(--bs-body-color);
  font-weight: 500;
}

.detail-value {
  color: #10b981;
  font-weight: 600;
}
</style>
