<template>
  <div class="card metric-card shadow-sm">
    <div class="card-body">
      <h6 class="card-title mb-3">Ритм коммитов (CB)</h6>
      <p class="text-muted small mb-4">Показывает, как часто и равномерно разработчики делают коммиты</p>
      
      <div class="metric-display mb-4">
        <div class="metric-value">{{ cbValue }}</div>
        <div class="metric-label">стандартное отклонение</div>
      </div>
      
      <div class="rhythm-card">
        <div class="rhythm-header">
          <span class="rhythm-label">Тип ритма:</span>
          <span class="badge" :class="rhythmClass">{{ rhythmType }}</span>
        </div>
        <p class="rhythm-description">{{ rhythmDescription }}</p>
        
        <div class="rhythm-info">
          <div class="info-block">
            <span class="info-title">Среднее время между коммитами</span>
            <span class="info-value">{{ averageInterval }}</span>
            <p class="info-hint">Разработчики делают коммиты примерно каждые {{ averageInterval }}</p>
          </div>
          
          <div class="info-block">
            <span class="info-title">Всего коммитов в период</span>
            <span class="info-value">{{ commits.length }}</span>
            <p class="info-hint">Анализируется активность за выбранный период</p>
          </div>
        </div>

        <div class="explanation-box">
          <p class="explanation-title">Что это означает:</p>
          <p class="explanation-text">
            {{ explanationText }}
          </p>
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

const calculateMetrics = () => {
  if (!props.commits || props.commits.length < 2) {
    return { burstiness: 0, avgInterval: 0 };
  }
  
  try {
    const times = props.commits
      .map(c => {
        if (!c || !c.created_at) return null;
        return new Date(c.created_at).getTime();
      })
      .filter(t => t !== null)
      .sort((a, b) => a - b);
    
    if (times.length < 2) return { burstiness: 0, avgInterval: 0 };
    
    const intervals = [];
    for (let i = 1; i < times.length; i++) {
      intervals.push(times[i] - times[i - 1]);
    }
    
    const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length;
    const variance = intervals.reduce((s, x) => s + (x - avgInterval) ** 2, 0) / intervals.length;
    const stddev = Math.sqrt(variance);
    
    return { 
      burstiness: isFinite(stddev) ? stddev : 0,
      avgInterval: isFinite(avgInterval) ? avgInterval : 0
    };
  } catch (e) {
    console.error('Ошибка расчета CB:', e);
    return { burstiness: 0, avgInterval: 0 };
  }
};

const metrics = computed(() => calculateMetrics());

const cbValue = computed(() => {
  const ms = metrics.value.burstiness;
  const minutes = ms / (1000 * 60);
  
  if (minutes < 1) return '< 1';
  if (minutes < 60) return Math.round(minutes);
  return Math.round(minutes / 60) + ' ч';
});

const averageInterval = computed(() => {
  const ms = metrics.value.avgInterval;
  
  if (ms < 1000 * 60) {
    return Math.round(ms / 1000) + ' сек';
  } else if (ms < 1000 * 60 * 60) {
    return Math.round(ms / (1000 * 60)) + ' мин';
  } else if (ms < 1000 * 60 * 60 * 24) {
    const hours = Math.round(ms / (1000 * 60 * 60) * 10) / 10;
    return hours + ' ч';
  } else {
    const days = Math.round(ms / (1000 * 60 * 60 * 24) * 10) / 10;
    return days + ' дн';
  }
});

const rhythmClass = computed(() => {
  const minutes = metrics.value.burstiness / (1000 * 60);
  
  if (minutes < 5) return 'bg-success';
  if (minutes < 30) return 'bg-info';
  if (minutes < 120) return 'bg-warning';
  return 'bg-danger';
});

const rhythmType = computed(() => {
  const minutes = metrics.value.burstiness / (1000 * 60);
  
  if (minutes < 5) return 'Регулярный';
  if (minutes < 30) return 'Стандартный';
  if (minutes < 120) return 'Нерегулярный';
  return 'Хаотичный';
});

const rhythmDescription = computed(() => {
  const minutes = metrics.value.burstiness / (1000 * 60);
  
  if (minutes < 5) {
    return 'Коммиты распределены очень равномерно. Разработка идет предсказуемо и планомерно.';
  } else if (minutes < 30) {
    return 'Коммиты происходят достаточно регулярно. Разработка идет стабильно в течение рабочего дня.';
  } else if (minutes < 120) {
    return 'Коммиты происходят не равномерно. Есть периоды интенсивной разработки и спокойствия.';
  } else {
    return 'Коммиты очень редкие и непредсказуемые. Возможна багетчинг (накопление и фиксация всех изменений сразу).';
  }
});

const explanationText = computed(() => {
  const minutes = metrics.value.burstiness / (1000 * 60);
  const avgMin = metrics.value.avgInterval / (1000 * 60);
  
  if (minutes < 5) {
    return `Разработчик делает маленькие, частые коммиты каждые ${Math.round(avgMin)} минут. Это хороший знак - код легче понять, проще найти баги, легче откатывать изменения. Профессиональный подход.`;
  } else if (minutes < 30) {
    return `Коммиты происходят примерно каждые ${averageInterval.value}. Это нормальный рабочий ритм - разработчики делают коммиты по завершении логических блоков работы. Стабильный и предсказуемый процесс.`;
  } else if (minutes < 120) {
    return `Разработчик чередует периоды активности и покоя. Возможно, работает над сложной фичей несколько часов, потом делает один большой коммит. Нормально, но можно улучшить.`;
  } else {
    return `Коммиты редкие (в среднем каждые ${averageInterval.value}). Вероятно, разработчик долго работает локально, а потом заливает всё сразу. Сложнее находить проблемы в таком коде. Рекомендуется более частые коммиты.`;
  }
});
</script>

<style scoped>
.metric-card {
  border: none;
  background: var(--bs-card-bg);
  border-radius: 8px;
  transition: all 0.2s;
  border-left: 4px solid #f59e0b;
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
  color: #f59e0b;
  line-height: 1;
}

.metric-label {
  font-size: 0.85rem;
  color: var(--bs-body-color);
  opacity: 0.7;
  margin-top: 8px;
  display: block;
}

.rhythm-card {
  background: var(--bs-tertiary-bg);
  border: 1px solid var(--bs-border-color);
  border-radius: 8px;
  padding: 16px;
}

.rhythm-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 12px;
  padding-bottom: 12px;
  border-bottom: 1px solid var(--bs-border-color);
}

.rhythm-label {
  font-weight: 600;
  font-size: 0.95rem;
  color: var(--bs-body-color);
}

.rhythm-description {
  font-size: 0.9rem;
  color: var(--bs-body-color);
  margin-bottom: 16px;
  line-height: 1.5;
  padding: 10px;
  background: var(--bs-body-bg);
  border-radius: 6px;
}

.rhythm-info {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  margin-bottom: 16px;
}

.info-block {
  background: var(--bs-body-bg);
  padding: 12px;
  border-radius: 6px;
  border-left: 3px solid #3b82f6;
}

.info-title {
  display: block;
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  color: var(--bs-body-color);
  opacity: 0.7;
  margin-bottom: 6px;
}

.info-value {
  display: block;
  font-size: 1.3rem;
  font-weight: 700;
  color: #3b82f6;
  margin-bottom: 6px;
}

.info-hint {
  font-size: 0.8rem;
  color: var(--bs-body-color);
  opacity: 0.65;
  margin: 0;
  line-height: 1.3;
}

.explanation-box {
  background: var(--bs-body-bg);
  border-left: 3px solid #8b5cf6;
  padding: 12px;
  border-radius: 6px;
}

.explanation-title {
  font-weight: 600;
  font-size: 0.9rem;
  color: var(--bs-body-color);
  margin-bottom: 8px;
}

.explanation-text {
  font-size: 0.85rem;
  color: var(--bs-body-color);
  line-height: 1.6;
  margin: 0;
}

.badge {
  padding: 4px 10px;
  font-size: 0.75rem;
  font-weight: 600;
}

@media (max-width: 768px) {
  .rhythm-info {
    grid-template-columns: 1fr;
  }
}
</style>
