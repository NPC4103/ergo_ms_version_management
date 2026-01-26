<template>
  <div class="card metric-card shadow-sm">
    <div class="card-body">
      <div class="d-flex justify-content-between align-items-start mb-3">
        <h6 class="card-title mb-0">Частота коммитов (CF)</h6>
        <span class="badge bg-info">{{ commits.length }}</span>
      </div>
      <p class="text-muted small mb-3">Количество коммитов за интервал времени</p>
      
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

const chartData = computed(() => {
  if (!props.commits || props.commits.length === 0) return { labels: [], datasets: [] };
  
  const daily = groupByDay(props.commits);
  const labels = Object.keys(daily).sort();
  
  if (labels.length === 0) return { labels: [], datasets: [] };
  
  const values = labels.map(d => daily[d]);
  
  return {
    labels,
    datasets: [{
      label: 'Коммиты',
      data: values,
      tension: 0.4,
      borderColor: '#3b82f6',
      backgroundColor: 'rgba(59, 130, 246, 0.1)',
      fill: true,
      pointBackgroundColor: '#3b82f6',
      pointBorderColor: '#fff',
      pointBorderWidth: 2,
      pointRadius: 4
    }]
  };
});

const chartOptions = {
  responsive: true,
  maintainAspectRatio: true,
  plugins: {
    legend: { display: false }
  },
  scales: {
    y: { beginAtZero: true, ticks: { stepSize: 1 } }
  }
};
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

.chart-wrapper {
  height: 250px;
}
</style>
