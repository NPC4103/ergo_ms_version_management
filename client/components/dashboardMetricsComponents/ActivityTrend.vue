<template>
  <div class="card metric-card shadow-sm">
    <div class="card-body">
      <div class="d-flex justify-content-between align-items-start mb-3">
        <h6 class="card-title mb-0">Тренд активности (CT)</h6>
        <span class="badge" :class="rhythmClass">{{ rhythmType }}</span>
      </div>
      <p class="text-muted small mb-3">Анализ ускорения / деградации активности</p>
      
      <div v-if="chartData && chartData.labels.length > 0" class="chart-wrapper">
        <Line :data="chartData" :options="chartOptions" />
      </div>
      <div v-else class="text-center py-4 text-muted">
        <p>Недостаточно данных</p>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Filler,
  Legend,
  Tooltip
} from 'chart.js';

ChartJS.register(LineElement, PointElement, LinearScale, CategoryScale, Filler, Legend, Tooltip);

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

const groupByDay = (data) => {
  const map = {};
  if (!data || !Array.isArray(data)) return map;
  
  for (const c of data) {
    if (!c || !c.created_at) continue;
    const d = c.created_at.slice(0, 10);
    map[d] = (map[d] || 0) + 1;
  }
  return map;
};

const calculateLinearRegression = (values) => {
  if (!values || values.length < 2) return { slope: 0, intercept: 0 };
  
  try {
    const n = values.length;
    const indices = Array.from({ length: n }, (_, i) => i);
    
    const meanX = indices.reduce((a, b) => a + b, 0) / n;
    const meanY = values.reduce((a, b) => a + b, 0) / n;
    
    const numerator = indices.reduce((sum, x, i) => sum + (x - meanX) * (values[i] - meanY), 0);
    const denominator = indices.reduce((sum, x) => sum + (x - meanX) ** 2, 0);
    
    if (denominator === 0) return { slope: 0, intercept: meanY };
    
    const slope = numerator / denominator;
    const intercept = meanY - slope * meanX;
    
    return { slope, intercept };
  } catch (e) {
    console.error('Ошибка расчета регрессии:', e);
    return { slope: 0, intercept: 0 };
  }
};

const trend = computed(() => {
  if (!props.commits || props.commits.length < 2) return { slope: 0, intercept: 0 };
  
  const daily = groupByDay(props.commits);
  const labels = Object.keys(daily).sort();
  if (labels.length < 2) return { slope: 0, intercept: 0 };
  
  const values = labels.map(d => daily[d]);
  return calculateLinearRegression(values);
});

const chartData = computed(() => {
  if (!props.commits || props.commits.length === 0) return { labels: [], datasets: [] };
  
  const daily = groupByDay(props.commits);
  const labels = Object.keys(daily).sort();
  
  if (labels.length === 0) return { labels: [], datasets: [] };
  
  const values = labels.map(d => daily[d]);
  const trendLine = values.map((_, i) => {
    return trend.value.slope * i + trend.value.intercept;
  });
  
  const smoothedValues = values.map(v => Math.max(0, v));
  const smoothedTrend = trendLine.map(v => Math.max(0, v));
  
  return {
    labels,
    datasets: [
      {
        label: 'Коммиты',
        data: smoothedValues,
        tension: 0.3,
        borderColor: '#8b5cf6',
        backgroundColor: 'rgba(139, 92, 246, 0.08)',
        fill: true,
        pointBackgroundColor: '#8b5cf6',
        pointBorderColor: '#fff',
        pointBorderWidth: 1.5,
        pointRadius: 2,
        borderWidth: 2
      },
      {
        label: 'Линия тренда',
        data: smoothedTrend,
        borderColor: '#f59e0b',
        borderDash: [5, 5],
        fill: false,
        tension: 0.3,
        pointRadius: 0,
        borderWidth: 2
      }
    ]
  };
});

const rhythmClass = computed(() => {
  const slope = trend.value.slope;
  if (slope > 0.05) return 'bg-success';
  if (slope < -0.05) return 'bg-danger';
  return 'bg-info';
});

const rhythmType = computed(() => {
  const slope = trend.value.slope;
  if (slope > 0.05) return 'Рост';
  if (slope < -0.05) return 'Падение';
  return 'Стабильно';
});

const chartOptions = {
  responsive: true,
  maintainAspectRatio: true,
  interaction: {
    intersect: false,
    mode: 'index'
  },
  plugins: {
    legend: {
      display: true,
      position: 'top',
      labels: {
        usePointStyle: true,
        padding: 15
      }
    },
    tooltip: {
      backgroundColor: 'rgba(0, 0, 0, 0.8)',
      padding: 12,
      titleFont: { size: 12 },
      bodyFont: { size: 11 },
      borderColor: 'rgba(255, 255, 255, 0.2)',
      borderWidth: 1
    }
  },
  scales: {
    y: {
      beginAtZero: true,
      min: 0,
      ticks: {
        stepSize: 1,
        callback: function(value) {
          return Math.max(0, Math.round(value));
        }
      },
      grid: {
        color: 'rgba(0, 0, 0, 0.05)'
      }
    },
    x: {
      grid: {
        display: false
      }
    }
  }
};
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

.chart-wrapper {
  height: 250px;
  position: relative;
}

/* Badge styling for stable state */
.bg-info {
  background-color: #0ea5e9 !important;
  color: white !important;
}

.bg-success {
  background-color: #10b981 !important;
  color: white !important;
}

.bg-danger {
  background-color: #ef4444 !important;
  color: white !important;
}
</style>
