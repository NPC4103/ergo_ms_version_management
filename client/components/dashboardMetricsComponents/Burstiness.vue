<template>
  <div class="card metric-card shadow-sm">
    <div class="card-body">
      <h6 class="card-title mb-3">Ритм коммитов (CB)</h6>
      <p class="text-muted small mb-4">Анализ скоплений активности разработки</p>
      
      <div class="metric-display mb-4">
        <div class="metric-value">{{ cbValue }}%</div>
        <div class="metric-label">нерегулярность разработки</div>
      </div>
      
      <div class="rhythm-card">
        <div class="rhythm-header">
          <span class="rhythm-label">Стиль разработки:</span>
          <span class="badge" :class="intensityClass">{{ intensityLabel }}</span>
        </div>
        <p class="rhythm-description">{{ intensityDescription }}</p>
        
        <div class="rhythm-info">
          <div class="info-block">
            <span class="info-title">Рабочих сессий</span>
            <span class="info-value">{{ metrics.sessions }}</span>
            <p class="info-hint">Количество отдельных периодов разработки</p>
          </div>
          
          <div class="info-block">
            <span class="info-title">Типичный перерыв</span>
            <span class="info-value">{{ averageInterval }}</span>
            <p class="info-hint">Среднее время между сессиями</p>
          </div>
        </div>

        <div class="explanation-box">
          <p class="explanation-title">Что это означает:</p>
          <p class="explanation-text">
            {{ intensityDescription }}
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

// Шаг 1: Подготовка timestamps
const getTimestamps = () => {
  return props.commits
    .map(c => new Date(c.created_at).getTime())
    .filter(t => Number.isFinite(t))
    .sort((a, b) => a - b);
};

// Шаг 2: Группировка в рабочие сессии (45 минут = один gap)
const getWorkSessions = (times) => {
  if (times.length === 0) return [];
  
  const SESSION_GAP = 45 * 60 * 1000; // 45 минут в мс
  const sessions = [];
  let current = [times[0]];
  
  for (let i = 1; i < times.length; i++) {
    if (times[i] - times[i - 1] <= SESSION_GAP) {
      current.push(times[i]);
    } else {
      sessions.push(current);
      current = [times[i]];
    }
  }
  sessions.push(current);
  
  return sessions;
};

// Шаг 3: Интервалы между сессиями
const getSessionGaps = (sessions) => {
  const gaps = [];
  
  for (let i = 1; i < sessions.length; i++) {
    const prevEnd = sessions[i - 1][sessions[i - 1].length - 1];
    const nextStart = sessions[i][0];
    gaps.push(nextStart - prevEnd);
  }
  
  return gaps;
};

// Квантиль (для IQR)
const quantile = (arr, q) => {
  if (arr.length === 0) return 0;
  const sorted = [...arr].sort((a, b) => a - b);
  const pos = (sorted.length - 1) * q;
  const base = Math.floor(pos);
  const rest = pos - base;
  
  if (sorted[base + 1] !== undefined) {
    return sorted[base] + rest * (sorted[base + 1] - sorted[base]);
  }
  return sorted[base];
};

// Медиана
const median = (arr) => quantile(arr, 0.5);

// Шаг 4: IQR-фильтрация выбросов
const filterOutliers = (gaps) => {
  if (gaps.length <= 3) return gaps; // Мало данных - не фильтруем
  
  const q1 = quantile(gaps, 0.25);
  const q3 = quantile(gaps, 0.75);
  const iqr = q3 - q1;
  
  return gaps.filter(x => x >= q1 - 1.5 * iqr && x <= q3 + 1.5 * iqr);
};

// Шаг 5 & 6: Расчёт burstiness через MAD (Median Absolute Deviation)
const calculateBurstiness = () => {
  try {
    const times = getTimestamps();
    
    if (times.length < 2) return { burstiness: 0, sessions: 0, avgGap: 0 };
    
    const sessions = getWorkSessions(times);
    
    if (sessions.length < 2) return { burstiness: 0, sessions: sessions.length, avgGap: 0 };
    
    // Получаем интервалы между сессиями
    let gaps = getSessionGaps(sessions);
    
    if (gaps.length === 0) return { burstiness: 0, sessions: sessions.length, avgGap: 0 };
    
    // Фильтруем выбросы
    const filtered = filterOutliers(gaps);
    
    if (filtered.length === 0) filtered = gaps; // Если все отфильтровались, берем оригинальные
    
    // Считаем медиану и MAD
    const med = median(filtered);
    
    if (med === 0) return { burstiness: 0, sessions: sessions.length, avgGap: 0 };
    
    const mad = median(filtered.map(x => Math.abs(x - med)));
    
    // Финальная метрика: burstiness = MAD / median
    const burstiness = mad / med;
    
    return {
      burstiness: isFinite(burstiness) ? burstiness : 0,
      sessions: sessions.length,
      avgGap: med
    };
  } catch (e) {
    console.error('Ошибка расчета burstiness:', e);
    return { burstiness: 0, sessions: 0, avgGap: 0 };
  }
};

const metrics = computed(() => calculateBurstiness());

// Интерпретация по новой шкале
const cbValue = computed(() => {
  // Конвертируем в процент нерегулярности (0-100%)
  const b = metrics.value.burstiness;
  const percent = Math.min(100, (b / 2) * 100); // Нормализуем: 2.0 = 100%
  return Math.round(percent);
});

const intensityClass = computed(() => {
  const b = metrics.value.burstiness;
  
  if (b < 0.3) return 'bg-success';
  if (b < 0.7) return 'bg-info';
  if (b < 1.5) return 'bg-warning';
  return 'bg-danger';
});

const intensityLabel = computed(() => {
  const b = metrics.value.burstiness;
  
  if (b < 0.3) return 'Равномерная';
  if (b < 0.7) return 'Смешанная';
  if (b < 1.5) return 'Сессионная';
  return 'Кластеризованная';
});

const intensityDescription = computed(() => {
  const b = metrics.value.burstiness;
  
  if (b < 0.3) {
    return 'Идеально равномерная разработка. Коммиты распределены очень стабильно во времени.';
  } else if (b < 0.7) {
    return 'Смешанный стиль разработки. Периодические сессии работы с нормальными паузами.';
  } else if (b < 1.5) {
    return 'Явно сессионная работа. Четкие периоды активности разделены длительными паузами.';
  } else {
    return 'Резко кластеризованная активность. Краткие всплески работы в непредсказуемое время.';
  }
});

const averageInterval = computed(() => {
  const ms = metrics.value.avgGap;
  
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
