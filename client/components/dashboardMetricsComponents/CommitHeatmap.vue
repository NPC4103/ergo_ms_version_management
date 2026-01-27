<template>
  <div class="card metric-card shadow-sm">
    <div class="card-body">
      <div class="d-flex justify-content-between align-items-start mb-3">
        <h6 class="card-title mb-0">Тепловая карта коммитов</h6>
        <span class="badge bg-secondary small-badge">
          {{ totalCommits }} коммитов
        </span>
      </div>
      <p class="text-muted small mb-3">
        Распределение коммитов по дням (как в GitHub)
      </p>

      <div v-if="days.length" class="heatmap-wrapper">
        <div class="heatmap-legend d-flex justify-content-between align-items-center mb-2">
          <span class="legend-label">Меньше</span>
          <div class="legend-colors d-flex align-items-center gap-1">
            <span
              v-for="level in 5"
              :key="`legend-${level}`"
              class="legend-cell"
              :class="`level-${level - 1}`"
            />
          </div>
          <span class="legend-label">Больше</span>
        </div>

        <div class="heatmap-grid">
          <div class="weekday-column">
            <span v-for="(day, index) in weekdayLabels" :key="index" class="weekday-label">
              {{ day }}
            </span>
          </div>

          <div class="days-scroll">
            <div class="days-grid">
              <div
                v-for="day in days"
                :key="day.date"
                class="day-cell"
                :class="`level-${day.intensity}`"
                :style="{ gridRowStart: day.weekdayGridRow }"
                :title="cellTitle(day)"
              />
            </div>
          </div>
        </div>
      </div>

      <div v-else class="text-center py-4 text-muted">
        <p>Недостаточно данных для построения тепловой карты</p>
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

const totalCommits = computed(() => props.commits?.length || 0);

// Полная шкала дней недели сверху вниз: Пн–Вс
const weekdayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

const buildHeatmapData = () => {
  if (!props.commits || !Array.isArray(props.commits) || !props.commits.length) {
    return [];
  }

  const daysCount = parseInt(props.period || '30', 10) || 30;
  const today = new Date();

  const countsByDate = {};
  for (const c of props.commits) {
    if (!c || !c.created_at) continue;
    const d = c.created_at.slice(0, 10);
    countsByDate[d] = (countsByDate[d] || 0) + 1;
  }

  const result = [];
  let maxCount = 0;

  for (let i = daysCount - 1; i >= 0; i--) {
    const date = new Date(today);
    date.setDate(today.getDate() - i);
    const iso = date.toISOString().slice(0, 10);
    const count = countsByDate[iso] || 0;
    maxCount = Math.max(maxCount, count);
    const weekday = date.getDay(); // 0 (Вс) - 6 (Сб)

    // Приводим к сетке, где верхняя строка — Пн, нижняя — Вс
    // Пн (1) -> 1, Вт (2) -> 2, ..., Сб (6) -> 6, Вс (0) -> 7
    const weekdayGridRow = weekday === 0 ? 7 : weekday;

    result.push({
      date: iso,
      weekday,
      weekdayGridRow,
      count,
    });
  }

  if (maxCount === 0) {
    return result.map((d) => ({ ...d, intensity: 0 }));
  }

  return result.map((d) => {
    // Для дней без коммитов всегда явно ставим нулевой уровень,
    // чтобы ячейки были чёрными независимо от вычислений интенсивности.
    if (!d.count) {
      return {
        ...d,
        intensity: 0,
      };
    }

    const ratio = d.count / maxCount;
    let level = 0;
    if (ratio > 0 && ratio <= 0.25) level = 1;
    else if (ratio <= 0.5) level = 2;
    else if (ratio <= 0.75) level = 3;
    else if (ratio > 0.75) level = 4;
    return {
      ...d,
      intensity: level,
    };
  });
};

const days = computed(() => buildHeatmapData());

const cellTitle = (day) => {
  if (!day) return '';
  const date = new Date(day.date);
  return `${day.count} коммит(ов) · ${date.toLocaleDateString()}`;
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

.small-badge {
  font-size: 0.75rem;
}

.heatmap-wrapper {
  width: 100%;
}

.heatmap-legend {
  font-size: 0.75rem;
}

.legend-label {
  opacity: 0.7;
}

.legend-colors {
  flex-wrap: nowrap;
}

.legend-cell {
  width: 14px;
  height: 14px;
  border-radius: 3px;
  border: 1px solid rgba(148, 163, 184, 0.6);
}

.heatmap-grid {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 6px;
  align-items: flex-start;
}

.weekday-column {
  display: flex;
  flex-direction: column;
  gap: 3px; /* совпадает с row-gap в .days-grid */
}

.weekday-label {
  font-size: 0.7rem;
  color: var(--bs-body-color);
  opacity: 0.5;
  height: 14px; /* совпадает с размером .day-cell */
  display: flex;
  align-items: center; /* вертикально центрируем текст относительно ячеек */
}

.days-scroll {
  overflow-x: auto;
  padding-bottom: 4px;
}

.days-grid {
  display: grid;
  grid-auto-flow: column;
  grid-template-rows: repeat(7, 1fr);
  grid-auto-columns: 14px;
  column-gap: 2px;
  row-gap: 3px;
  min-height: 84px;
  width: max-content;
}

.day-cell {
  width: 14px;
  height: 14px;
  border-radius: 3px;
  border: 1px solid rgba(148, 163, 184, 0.4);
  background-color: rgba(15, 23, 42, 0.05);
  transition: transform 0.1s ease, box-shadow 0.1s ease;
}

.day-cell:hover {
  transform: scale(1.15);
  box-shadow: 0 0 0 1px rgba(148, 163, 184, 0.7);
}

.day-cell.level-0 {
  background-color: #000000;
}

.legend-cell.level-0 {
  background-color: #000000;
}

.day-cell.level-1,
.legend-cell.level-1 {
  background-color: rgba(59, 130, 246, 0.2);
}

.day-cell.level-2,
.legend-cell.level-2 {
  background-color: rgba(59, 130, 246, 0.45);
}

.day-cell.level-3,
.legend-cell.level-3 {
  background-color: rgba(37, 99, 235, 0.75);
}

.day-cell.level-4,
.legend-cell.level-4 {
  background-color: rgba(30, 64, 175, 0.95);
}

@media (max-width: 768px) {
  .heatmap-grid {
    grid-template-columns: auto 1fr;
  }

  .legend-label {
    font-size: 0.7rem;
  }
}
</style>

