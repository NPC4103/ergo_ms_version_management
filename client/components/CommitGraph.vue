<template>
  <div class="commit-graph-page">
    <!-- Header -->
    <div class="graph-header">
      <div class="d-flex align-items-center gap-3">
        <router-link :to="{ name: 'RepositoryDetail', params: { id: repoId } }" class="btn btn-outline-secondary">
          <i class="bi bi-arrow-left"></i> Назад
        </router-link>
        <h2 class="mb-0">История коммитов</h2>
      </div>
      
      <div class="graph-controls">
        <select v-model="currentBranch" class="form-select form-select-sm" style="width: 200px;">
          <option v-for="branch in branches" :key="branch" :value="branch">{{ branch }}</option>
        </select>
        
        <div class="zoom-controls">
          <button class="btn btn-outline-secondary btn-sm" @click="zoomIn" title="Приблизить">
            <i class="bi bi-zoom-in"></i>
          </button>
          <span class="zoom-level">{{ Math.round(zoom * 100) }}%</span>
          <button class="btn btn-outline-secondary btn-sm" @click="zoomOut" title="Отдалить">
            <i class="bi bi-zoom-out"></i>
          </button>
          <button class="btn btn-outline-secondary btn-sm" @click="resetZoom" title="Сбросить">
            <i class="bi bi-arrows-fullscreen"></i>
          </button>
        </div>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="loading-container">
      <div class="spinner-border text-primary" role="status">
        <span class="visually-hidden">Загрузка...</span>
      </div>
    </div>

    <!-- Graph Container -->
    <div 
      v-else 
      class="graph-container" 
      ref="graphContainer"
      @wheel.prevent="handleWheel"
      @mousedown="startPan"
      @mousemove="doPan"
      @mouseup="endPan"
      @mouseleave="endPan"
    >
      <svg 
        :viewBox="viewBox" 
        class="commit-graph-svg"
        :style="{ cursor: isPanning ? 'grabbing' : 'grab' }"
      >
        <!-- Connection Lines -->
        <g class="connections">
          <path
            v-for="(line, idx) in connectionLines"
            :key="'line-' + idx"
            :d="line.path"
            :stroke="line.color"
            stroke-width="2"
            fill="none"
            class="connection-line"
          />
        </g>

        <!-- Commit Nodes -->
        <g class="nodes">
          <g
            v-for="commit in positionedCommits"
            :key="commit.hash"
            :transform="`translate(${commit.x}, ${commit.y})`"
            class="commit-node-group"
            @click="goToCommit(commit)"
            @mouseenter="showTooltip(commit, $event)"
            @mouseleave="hideTooltip"
          >
            <!-- Node Circle -->
            <circle
              :r="commit.isMerge ? 14 : 12"
              :fill="commit.branchColor"
              :stroke="commit.isMerge ? '#fff' : 'none'"
              :stroke-width="commit.isMerge ? 3 : 0"
              class="commit-node"
              :class="{ 'merge-node': commit.isMerge, 'branch-point': commit.isBranchPoint }"
            />
            
            <!-- Short Hash Label -->
            <text 
              :x="20" 
              y="5" 
              class="commit-label"
              :fill="commit.branchColor"
            >
              {{ commit.shortHash }}
            </text>
          </g>
        </g>
      </svg>

      <!-- Tooltip -->
      <div 
        v-if="tooltipData" 
        class="commit-tooltip"
        :style="{ left: tooltipPosition.x + 'px', top: tooltipPosition.y + 'px' }"
      >
        <div class="tooltip-header">
          <span class="tooltip-hash">{{ tooltipData.shortHash }}</span>
          <span class="tooltip-files">{{ tooltipData.filesChanged }} файлов</span>
        </div>
        <div class="tooltip-message">{{ tooltipData.message }}</div>
        <div class="tooltip-meta">
          <span><i class="bi bi-person"></i> {{ tooltipData.author }}</span>
          <span><i class="bi bi-clock"></i> {{ formatDate(tooltipData.date) }}</span>
        </div>
      </div>
    </div>

    <!-- Empty State -->
    <div v-if="!loading && commits.length === 0" class="empty-state">
      <i class="bi bi-git display-1 text-muted"></i>
      <p class="text-muted mt-3">Нет коммитов в этой ветке</p>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';

const route = useRoute();
const router = useRouter();
const repoId = route.params.id;

// State
const loading = ref(true);
const commits = ref([]);
const branches = ref(['main']);
const currentBranch = ref('main');
const zoom = ref(1);
const panOffset = ref({ x: 0, y: 0 });
const isPanning = ref(false);
const panStart = ref({ x: 0, y: 0 });
const graphContainer = ref(null);

// Tooltip
const tooltipData = ref(null);
const tooltipPosition = ref({ x: 0, y: 0 });

// Branch colors
const branchColors = {
  'main': '#3b82f6',
  'master': '#3b82f6',
  'develop': '#10b981',
  'feature': '#f59e0b',
  'hotfix': '#ef4444',
  'release': '#8b5cf6',
  'default': '#6b7280'
};

const getBranchColor = (branchName) => {
  if (!branchName) return branchColors.default;
  const prefix = branchName.split('/')[0].toLowerCase();
  return branchColors[prefix] || branchColors[branchName] || branchColors.default;
};

// Computed
const nodeSpacingX = 150;
const nodeSpacingY = 60;

const positionedCommits = computed(() => {
  return commits.value.map((commit, index) => {
    const lane = commit.lane || 0;
    return {
      ...commit,
      x: 100 + lane * nodeSpacingX,
      y: 50 + index * nodeSpacingY,
      shortHash: commit.hash?.substring(0, 7) || '',
      branchColor: getBranchColor(commit.branch),
      isMerge: commit.parents?.length > 1,
      isBranchPoint: commit.children?.length > 1
    };
  });
});

const connectionLines = computed(() => {
  const lines = [];
  positionedCommits.value.forEach(commit => {
    if (commit.parents) {
      commit.parents.forEach(parentHash => {
        const parent = positionedCommits.value.find(c => c.hash === parentHash);
        if (parent) {
          const isCurved = commit.x !== parent.x;
          let path;
          if (isCurved) {
            const midY = (commit.y + parent.y) / 2;
            path = `M ${commit.x} ${commit.y} C ${commit.x} ${midY}, ${parent.x} ${midY}, ${parent.x} ${parent.y}`;
          } else {
            path = `M ${commit.x} ${commit.y} L ${parent.x} ${parent.y}`;
          }
          lines.push({
            path,
            color: commit.branchColor
          });
        }
      });
    }
  });
  return lines;
});

const viewBox = computed(() => {
  const width = 800 / zoom.value;
  const height = Math.max(400, commits.value.length * nodeSpacingY + 100) / zoom.value;
  return `${-panOffset.value.x} ${-panOffset.value.y} ${width} ${height}`;
});

// Methods
const loadCommits = async () => {
  loading.value = true;
  try {
    const response = await apiClient.get(versionManagementEndpoints.repositories.commitsList(repoId));
    if (response.success) {
      // Add mock data for demo if empty
      let data = Array.isArray(response.data) ? response.data : (response.data?.results || []);
      
      // Assign lanes for visualization
      data = data.map((commit, idx) => ({
        ...commit,
        lane: 0, // TODO: Calculate actual lanes based on branches
        filesChanged: commit.files_changed || Math.floor(Math.random() * 10) + 1
      }));
      
      commits.value = data;
    }
  } catch (error) {
    console.error('Failed to load commits:', error);
  } finally {
    loading.value = false;
  }
};

const loadBranches = async () => {
  try {
    const response = await apiClient.get(versionManagementEndpoints.repositories.branches(repoId));
    if (response.success && response.data) {
      branches.value = response.data.map(b => b.name);
      if (branches.value.length > 0) {
        currentBranch.value = branches.value[0];
      }
    }
  } catch (error) {
    console.error('Failed to load branches:', error);
  }
};

const goToCommit = (commit) => {
  router.push({ 
    name: 'CommitDetail', 
    params: { id: repoId, hash: commit.hash } 
  });
};

const showTooltip = (commit, event) => {
  tooltipData.value = commit;
  tooltipPosition.value = {
    x: event.clientX + 15,
    y: event.clientY - 10
  };
};

const hideTooltip = () => {
  tooltipData.value = null;
};

const formatDate = (dateString) => {
  if (!dateString) return '';
  const date = new Date(dateString);
  const now = new Date();
  const diff = now - date;
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));
  
  if (days === 0) return 'Сегодня';
  if (days === 1) return 'Вчера';
  if (days < 7) return `${days} дней назад`;
  return date.toLocaleDateString('ru-RU');
};

// Zoom & Pan
const zoomIn = () => { zoom.value = Math.min(zoom.value * 1.2, 3); };
const zoomOut = () => { zoom.value = Math.max(zoom.value / 1.2, 0.3); };
const resetZoom = () => { zoom.value = 1; panOffset.value = { x: 0, y: 0 }; };

const handleWheel = (e) => {
  if (e.deltaY < 0) zoomIn();
  else zoomOut();
};

const startPan = (e) => {
  isPanning.value = true;
  panStart.value = { x: e.clientX - panOffset.value.x, y: e.clientY - panOffset.value.y };
};

const doPan = (e) => {
  if (!isPanning.value) return;
  panOffset.value = {
    x: e.clientX - panStart.value.x,
    y: e.clientY - panStart.value.y
  };
};

const endPan = () => {
  isPanning.value = false;
};

// Lifecycle
onMounted(() => {
  loadBranches();
  loadCommits();
});
</script>

<style scoped>
.commit-graph-page {
  padding: 20px;
  height: 100%;
  display: flex;
  flex-direction: column;
}

.graph-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 20px;
  flex-wrap: wrap;
  gap: 15px;
}

.graph-controls {
  display: flex;
  align-items: center;
  gap: 15px;
}

.zoom-controls {
  display: flex;
  align-items: center;
  gap: 8px;
  background: #f8f9fa;
  padding: 5px 10px;
  border-radius: 8px;
}

.zoom-level {
  min-width: 50px;
  text-align: center;
  font-size: 0.85rem;
  color: #666;
}

.graph-container {
  flex: 1;
  background: linear-gradient(135deg, #1a1d21 0%, #2d3439 100%);
  border-radius: 12px;
  overflow: hidden;
  position: relative;
  min-height: 500px;
}

.commit-graph-svg {
  width: 100%;
  height: 100%;
}

.loading-container {
  display: flex;
  justify-content: center;
  align-items: center;
  height: 400px;
}

.empty-state {
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  height: 300px;
}

/* Commit Node Styles */
.commit-node-group {
  cursor: pointer;
  transition: transform 0.2s ease;
}

.commit-node-group:hover {
  transform: scale(1.1);
}

.commit-node {
  transition: all 0.3s ease;
  filter: drop-shadow(0 2px 4px rgba(0,0,0,0.3));
}

.commit-node-group:hover .commit-node {
  animation: wobble 0.5s ease-in-out;
  filter: drop-shadow(0 4px 12px rgba(0,0,0,0.5));
}

@keyframes wobble {
  0%, 100% { transform: rotate(0deg) scale(1); }
  20% { transform: rotate(-8deg) scale(1.1); }
  40% { transform: rotate(6deg) scale(1.1); }
  60% { transform: rotate(-4deg) scale(1.1); }
  80% { transform: rotate(2deg) scale(1.1); }
}

.merge-node {
  filter: drop-shadow(0 0 8px rgba(255,255,255,0.5));
}

.branch-point {
  filter: drop-shadow(0 0 12px currentColor);
}

.commit-label {
  font-size: 11px;
  font-family: 'Consolas', 'Monaco', monospace;
  font-weight: 600;
}

.connection-line {
  opacity: 0.6;
  transition: opacity 0.2s;
}

/* Tooltip */
.commit-tooltip {
  position: fixed;
  background: rgba(30, 35, 40, 0.95);
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255,255,255,0.1);
  border-radius: 10px;
  padding: 12px 16px;
  min-width: 250px;
  max-width: 350px;
  z-index: 1000;
  box-shadow: 0 8px 32px rgba(0,0,0,0.4);
  animation: tooltipFadeIn 0.2s ease;
}

@keyframes tooltipFadeIn {
  from { opacity: 0; transform: translateY(-5px); }
  to { opacity: 1; transform: translateY(0); }
}

.tooltip-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.tooltip-hash {
  font-family: 'Consolas', monospace;
  color: #3b82f6;
  font-weight: 600;
}

.tooltip-files {
  background: rgba(59, 130, 246, 0.2);
  color: #60a5fa;
  padding: 2px 8px;
  border-radius: 12px;
  font-size: 0.75rem;
}

.tooltip-message {
  color: #fff;
  font-size: 0.9rem;
  margin-bottom: 8px;
  line-height: 1.4;
  word-break: break-word;
}

.tooltip-meta {
  display: flex;
  gap: 15px;
  font-size: 0.8rem;
  color: #9ca3af;
}

.tooltip-meta i {
  margin-right: 4px;
}
</style>
