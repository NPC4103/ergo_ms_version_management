<template>
  <div class="card metric-card shadow-sm">
    <div class="card-body">
      <h6 class="card-title mb-3">Семантические изменения (CSCI)</h6>
      <p class="text-muted small mb-4">Оценка инженерной глубины и логической сложности коммитов</p>
      
      <div class="metric-display mb-4">
        <div class="metric-value">{{ csciValue }}</div>
        <div class="metric-label">средний индекс семантичности (0-100)</div>
      </div>

      <div class="csci-card">
        <div class="csci-badge" :class="csciClass">{{ csciLabel }}</div>
        <p class="csci-description">{{ csciDescription }}</p>

        <div class="csci-stats">
          <div class="stat-item">
            <span class="stat-label">Среднее значение</span>
            <span class="stat-value">{{ (avgCSCI * 100).toFixed(1) }}</span>
          </div>
          <div class="stat-item">
            <span class="stat-label">Максимум</span>
            <span class="stat-value">{{ (maxCSCI * 100).toFixed(1) }}</span>
          </div>
        </div>

        <div class="semantic-table">
          <div class="semantic-header">Анализируемые конструкции:</div>
          <div class="semantic-rows">
            <div class="semantic-row">Условия (if/else/switch) → <strong>1.0</strong></div>
            <div class="semantic-row">Циклы (for/while/map) → <strong>0.9</strong></div>
            <div class="semantic-row">Обработка ошибок (try/catch) → <strong>1.0</strong></div>
            <div class="semantic-row">Возврат данных (return) → <strong>0.8</strong></div>
            <div class="semantic-row">Функции/методы → <strong>0.7</strong></div>
            <div class="semantic-row">Классы/структуры → <strong>0.7</strong></div>
            <div class="semantic-row">Комментарии → <strong>0.2</strong></div>
            <div class="semantic-row">Форматирование → <strong>0.05</strong></div>
          </div>
        </div>

        <div class="methodology-note">
          <small class="text-muted">
            <strong>Примечание:</strong> В текущей версии используется демонстрационный генератор значений CSCI. 
            Архитектура полностью готова к реальному анализу при подключении API diff. 
            Функция calculateCSCI реализована и ожидает поступления diff данных.
          </small>
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

// Паттерны семантических конструкций
const SEMANTIC_PATTERNS = {
  condition: { regex: /\b(if|else|switch|case|ternary|elseif)\b/gi, weight: 1.0 },
  loop: { regex: /\b(for|while|foreach|do|map|reduce|filter)\b/gi, weight: 0.9 },
  error: { regex: /\b(try|catch|throw|throws|finally|Error|Exception)\b/gi, weight: 1.0 },
  return: { regex: /\breturn\b/gi, weight: 0.8 },
  function: { regex: /\b(function|def|=>|lambda|fn)\b/gi, weight: 0.7 },
  class: { regex: /\b(class|struct|interface|enum|type)\b/gi, weight: 0.7 },
  comment: { regex: /(\/\/|\/\*|\*\/|#|'''|""")/gi, weight: 0.2 },
  formatting: { regex: /[{};\n]/g, weight: 0.05 }
};

// Расчёт CSCI для одного diff
const calculateCSCI = (diffText) => {
  if (!diffText) return 0;

  const lines = diffText.split('\n');
  let totalWeight = 0;
  let changedLines = 0;

  for (const line of lines) {
    // Пропускаем служебные строки diff
    if (line.startsWith('+++') || line.startsWith('---') || line.startsWith('@@')) continue;
    
    // Считаем только измененные строки (добавленные или удаленные)
    if (line.startsWith('+') || line.startsWith('-')) {
      changedLines++;
      
      const content = line.substring(1); // Удаляем +/-
      
      // Подсчитываем семантические конструкции
      for (const [, pattern] of Object.entries(SEMANTIC_PATTERNS)) {
        const matches = content.match(pattern.regex) || [];
        totalWeight += matches.length * pattern.weight;
      }
    }
  }

  if (changedLines === 0) return 0;
  return totalWeight / changedLines;
};

// Демонстрационный генератор значений (при отсутствии API diff)
const generateDemoCSCI = (commitCount) => {
  // Генерируем значения, отражающие разные типы изменений
  const types = [0.08, 0.25, 0.45, 0.65]; // cosmetic, usual, logic, serious
  
  return Array.from({ length: commitCount }, () => {
    const baseValue = types[Math.floor(Math.random() * types.length)];
    const variance = (Math.random() - 0.5) * 0.1;
    return Math.max(0, Math.min(1, baseValue + variance));
  });
};

// Расчёт CSCI для всех коммитов
const csciValues = computed(() => {
  // Когда API diff будет доступен, раскомментировать:
  // return props.commits
  //   .map(c => calculateCSCI(c.diff))
  //   .filter(v => v !== null);
  
  // Текущая демонстрационная версия:
  return generateDemoCSCI(props.commits.length);
});

const avgCSCI = computed(() => {
  if (csciValues.value.length === 0) return 0;
  const sum = csciValues.value.reduce((a, b) => a + b, 0);
  return sum / csciValues.value.length;
});

const maxCSCI = computed(() => {
  if (csciValues.value.length === 0) return 0;
  return Math.max(...csciValues.value);
});

const csciValue = computed(() => {
  return (avgCSCI.value * 100).toFixed(0);
});

const csciClass = computed(() => {
  if (avgCSCI.value > 0.6) return 'badge-serious';
  if (avgCSCI.value > 0.35) return 'badge-logic';
  if (avgCSCI.value > 0.15) return 'badge-usual';
  return 'badge-cosmetic';
});

const csciLabel = computed(() => {
  if (avgCSCI.value > 0.6) return 'Серьёзная переработка';
  if (avgCSCI.value > 0.35) return 'Логические изменения';
  if (avgCSCI.value > 0.15) return 'Обычные правки';
  return 'Косметические изменения';
});

const csciDescription = computed(() => {
  if (avgCSCI.value > 0.6) {
    return 'Коммиты содержат значительные логические изменения. Глубокая инженерная переработка с условиями, циклами и обработкой ошибок.';
  } else if (avgCSCI.value > 0.35) {
    return 'Коммиты затрагивают основную логику программы. Содержательные изменения функциональности и архитектуры.';
  } else if (avgCSCI.value > 0.15) {
    return 'Коммиты с обычными исправлениями и улучшениями. Нормальная разработка с изменением отдельных функций.';
  } else {
    return 'Коммиты в основном косметические: форматирование, комментарии, минорные правки без влияния на логику.';
  }
});
</script>

<style scoped>
.metric-card {
  border: none;
  background: var(--bs-card-bg);
  border-radius: 8px;
  transition: all 0.2s;
  border-left: 4px solid #8b5cf6;
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
  color: #8b5cf6;
  line-height: 1;
}

.metric-label {
  font-size: 0.85rem;
  color: var(--bs-body-color);
  opacity: 0.7;
  margin-top: 8px;
  display: block;
}

.csci-card {
  background: var(--bs-tertiary-bg);
  border: 1px solid var(--bs-border-color);
  border-radius: 8px;
  padding: 16px;
}

.csci-badge {
  display: inline-block;
  padding: 6px 12px;
  border-radius: 4px;
  font-weight: 600;
  font-size: 0.85rem;
  margin-bottom: 12px;
}

.badge-serious {
  background: #dc2626;
  color: white;
}

.badge-logic {
  background: #f59e0b;
  color: white;
}

.badge-usual {
  background: #3b82f6;
  color: white;
}

.badge-cosmetic {
  background: #6b7280;
  color: white;
}

.csci-description {
  font-size: 0.9rem;
  color: var(--bs-body-color);
  margin-bottom: 12px;
  line-height: 1.5;
}

.csci-stats {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--bs-border-color);
}

.stat-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.stat-label {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--bs-body-color);
  opacity: 0.7;
  text-transform: uppercase;
}

.stat-value {
  font-size: 1.3rem;
  font-weight: 700;
  color: #8b5cf6;
}

.semantic-table {
  margin-top: 16px;
  padding-top: 12px;
  border-top: 1px solid var(--bs-border-color);
}

.semantic-header {
  font-weight: 600;
  font-size: 0.85rem;
  color: var(--bs-body-color);
  margin-bottom: 8px;
}

.semantic-rows {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.semantic-row {
  font-size: 0.8rem;
  color: var(--bs-body-color);
  opacity: 0.8;
}

.methodology-note {
  margin-top: 16px;
  padding: 12px;
  background: var(--bs-tertiary-bg);
  border-left: 3px solid #8b5cf6;
  border-radius: 4px;
}
</style>
