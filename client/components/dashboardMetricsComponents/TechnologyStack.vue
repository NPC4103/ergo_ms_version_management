<template>
  <div class="card metric-card shadow-sm">
    <div class="card-body">
      <h6 class="card-title mb-3">Технологический стек (TSD)</h6>
      <p class="text-muted small mb-4">
        Анализ использования технологий в проекте
      </p>
      
      <!-- Визуализация: Горизонтальные полосы -->
      <div class="tech-list">
        <div v-for="lang in sortedTechnologies" :key="lang.name" class="tech-item">
          <div class="tech-header">
            <span class="tech-name">{{ lang.name }}</span>
            <span class="tech-stats">
              <span class="tech-percent">{{ lang.percent }}%</span>
              <span class="tech-count">({{ lang.count }} упоминаний)</span>
            </span>
          </div>
          <div class="tech-bar-container">
            <div class="tech-bar" :style="{ backgroundColor: lang.color }">
              <div class="tech-bar-label">{{ lang.percent }}%</div>
            </div>
          </div>
        </div>
      </div>

      <!-- Если нет данных -->
      <div v-if="sortedTechnologies.length === 0" class="no-data">
        <p class="text-center text-muted py-4">
          Нет данных для анализа
        </p>
      </div>

      <!-- Сводка по технологиям -->
      <div v-if="sortedTechnologies.length > 0" class="tech-summary">
        <div class="summary-grid">
          <div class="summary-item">
            <span class="summary-label">Всего упоминаний</span>
            <span class="summary-value">{{ totalFiles }}</span>
          </div>
          <div class="summary-item">
            <span class="summary-label">Уникальных языков</span>
            <span class="summary-value">{{ sortedTechnologies.length }}</span>
          </div>
          <div class="summary-item">
            <span class="summary-label">Основной язык</span>
            <span class="summary-value">{{ sortedTechnologies[0]?.name || '-' }}</span>
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
  '.css': 'CSS',
  '.scss': 'SCSS',
  '.json': 'JSON',
  '.xml': 'XML',
  '.yaml': 'YAML',
  '.yml': 'YAML',
  '.sql': 'SQL',
  '.sh': 'Bash'
};

const LANGUAGE_COLORS = {
  'TypeScript': '#3178c6',
  'JavaScript': '#f7df1e',
  'Python': '#3776ab',
  'C#': '#239120',
  'Java': '#007396',
  'Go': '#00add8',
  'Rust': '#ce422b',
  'PHP': '#777bb4',
  'Ruby': '#cc342d',
  'Swift': '#fa7343',
  'Kotlin': '#7f52ff',
  'Vue': '#42b983',
  'HTML': '#e34c26',
  'CSS': '#563d7c',
  'SCSS': '#c6538c',
  'JSON': '#999999',
  'SQL': '#cc5500',
  'Bash': '#4eaa25',
  'XML': '#0066cc',
  'YAML': '#cb171e',
  'C': '#a8661d',
  'C++': '#00599c',
  'Other': '#999999'
};

const extractExtensions = (text) => {
  if (!text) return [];
  const matches = text.match(/\.(js|ts|py|cs|cpp|c|java|go|rs|php|rb|swift|kt|jsx|tsx|vue|html|css|scss|json|xml|yaml|yml|sql|sh)\b/gi);
  return matches || [];
};

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
      percent: parseFloat(((count / totalFiles) * 100).toFixed(1)),
      count,
      color: LANGUAGE_COLORS[name] || '#999999'
    }))
    .sort((a, b) => parseFloat(b.percent) - parseFloat(a.percent));
};

const sortedTechnologies = computed(() => calculateTSD());

const totalFiles = computed(() => {
  return sortedTechnologies.value.reduce((sum, lang) => sum + lang.count, 0);
});
</script>

<style scoped>
.metric-card {
  border: none;
  background: var(--bs-card-bg);
  border-radius: 8px;
  transition: all 0.2s;
  border-left: 4px solid #3b82f6;
}

.metric-card:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15) !important;
}

.card-title {
  font-weight: 600;
  color: var(--bs-body-color);
}

.tech-list {
  display: flex;
  flex-direction: column;
  gap: 16px;
  margin-bottom: 20px;
}

.tech-item {
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.tech-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.tech-name {
  font-weight: 600;
  color: var(--bs-body-color);
  font-size: 0.95rem;
}

.tech-stats {
  display: flex;
  align-items: center;
  gap: 8px;
}

.tech-percent {
  font-weight: 700;
  color: #3b82f6;
  font-size: 1rem;
  min-width: 45px;
  text-align: right;
}

.tech-count {
  font-size: 0.8rem;
  color: var(--bs-body-color);
  opacity: 0.6;
}

.tech-bar-container {
  display: flex;
  align-items: center;
}

.tech-bar {
  height: 32px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: flex-end;
  padding-right: 12px;
  color: white;
  font-weight: 600;
  font-size: 0.8rem;
  min-width: 40px;
  transition: all 0.3s ease;
}

.tech-bar:hover {
  filter: brightness(1.1);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
}

.tech-bar-label {
  color: white;
  text-shadow: 0 1px 2px rgba(0, 0, 0, 0.2);
}

.no-data {
  background: var(--bs-tertiary-bg);
  border-radius: 8px;
  margin-bottom: 16px;
}

.tech-summary {
  background: var(--bs-tertiary-bg);
  border-radius: 8px;
  padding: 16px;
  margin-bottom: 16px;
}

.summary-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
}

.summary-item {
  display: flex;
  flex-direction: column;
  gap: 6px;
  text-align: center;
}

.summary-label {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--bs-body-color);
  opacity: 0.7;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}

.summary-value {
  font-size: 1.5rem;
  font-weight: 700;
  color: #3b82f6;
}
</style>
