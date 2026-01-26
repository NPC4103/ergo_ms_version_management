<template>
  <div class="metrics-dashboard">

    <!-- Header -->
    <div class="header mb-4">
      <div class="d-flex justify-content-between align-items-start mb-3">
        <div>
          <h1>Метрики репозитория</h1>
          <div class="repo-info mt-2">
            <span class="badge badge-id">ID: {{ repo?.public_id?.substring(0, 8) }}</span>
          </div>
        </div>
        <router-link
          :to="{ name: 'RepositoryDetail', params: { id: repoId } }"
          class="btn btn-outline-secondary btn-sm">
          Назад
        </router-link>
      </div>
    </div>

    <!-- Toolbar -->
    <div class="toolbar mb-4">
      <div class="toolbar-content">
        <div class="toolbar-left">
          <div class="filter-group">
            <label class="filter-label">Период</label>
            <select v-model="period" @change="loadData" class="filter-select">
              <option value="7">7 дней</option>
              <option value="30">30 дней</option>
              <option value="90">90 дней</option>
              <option value="365">1 год</option>
            </select>
          </div>

          <div class="filter-divider"></div>

          <div class="filter-group">
            <label class="filter-label">Ветка</label>
            <select v-model="selectedBranch" @change="filterByBranch" class="filter-select">
              <option value="">Все ветки</option>
              <option v-for="branch in branches" :key="branch" :value="branch">
                {{ branch }}
              </option>
            </select>
          </div>
        </div>

        <button @click="refreshMetrics" class="btn-refresh" :class="{ loading: loading }">
          <span class="refresh-icon">↻</span>
          <span class="refresh-text">Обновить</span>
        </button>
      </div>
    </div>

    <!-- Error Alert -->
    <div v-if="errorMessage" class="alert alert-danger alert-dismissible fade show mb-4">
      <strong>Ошибка:</strong> {{ errorMessage }}
      <button type="button" class="btn-close" @click="errorMessage = ''"></button>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="text-center py-5">
      <div class="spinner-border text-primary"></div>
      <p class="mt-3 text-muted">Загрузка метрик...</p>
    </div>

    <!-- No Data -->
    <div v-else-if="!filteredCommits || filteredCommits.length === 0" class="alert alert-info">
      <strong>Нет данных</strong> за выбранный период
    </div>

    <!-- Metrics Grid -->
    <div v-else class="row g-4">
      <!-- Row 1: Frequency & Trend -->
      <div class="col-lg-6">
        <CommitFrequency 
          :key="`cf-${filteredCommits.length}`"
          :commits="filteredCommits" 
          :period="period" 
        />
      </div>
      <div class="col-lg-6">
        <ActivityTrend 
          :key="`at-${filteredCommits.length}`"
          :commits="filteredCommits" 
          :period="period" 
        />
      </div>

      <!-- Row 2: Burstiness (Full Width) -->
      <div class="col-lg-12">
        <Burstiness 
          :key="`b-${filteredCommits.length}`"
          :commits="filteredCommits" 
          :period="period" 
        />
      </div>

      <!-- Row 3: Technology Stack & Modernity -->
      <div class="col-lg-6">
        <TechnologyStack 
          :key="`tsd-${filteredCommits.length}`"
          :commits="filteredCommits" 
          :period="period" 
        />
      </div>
      <div class="col-lg-6">
        <ModernityIndex 
          :key="`mti-${filteredCommits.length}`"
          :commits="filteredCommits" 
          :period="period" 
        />
      </div>

      <!-- Row 4: Semantic Changes (Full Width) -->
      <div class="col-lg-12">
        <SemanticChange 
          :key="`csci-${filteredCommits.length}`"
          :commits="filteredCommits" 
          :period="period" 
        />
      </div>
    </div>

  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { useToast } from 'vue-toastification';

import CommitFrequency from './dashboardMetricsComponents/CommitFrequency.vue';
import ActivityTrend from './dashboardMetricsComponents/ActivityTrend.vue';
import Burstiness from './dashboardMetricsComponents/Burstiness.vue';
import TechnologyStack from './dashboardMetricsComponents/TechnologyStack.vue';
import ModernityIndex from './dashboardMetricsComponents/ModernityIndex.vue';
import SemanticChange from './dashboardMetricsComponents/SemanticChange.vue';

const route = useRoute();
const toast = useToast();
const repoId = route.params.id;

const loading = ref(true);
const errorMessage = ref('');
const repo = ref(null);
const commitsData = ref([]);
const branches = ref([]);
const period = ref('30');
const selectedBranch = ref('');

/* ============ Фильтрация по ветке ============ */

const filteredCommits = computed(() => {
  if (!selectedBranch.value) return commitsData.value;
  return commitsData.value.filter(c => c.branch === selectedBranch.value);
});

const filterByBranch = () => {
  // Триггер для перерендера компонентов через key
};

/* ============ MOCK DATA ============ */

const mockRepository = {
  public_id: '550e8400-e29b-41d4-a716-446655440000',
  name: 'Version Manager',
  description: 'Version management система для отслеживания коммитов',
  is_private: false,
  is_read_only: false,
  owner_id: 1,
  branch_count: 3,
  default_branch: { id: 1, name: 'main' },
  is_editable: true,
  user_role: 'owner',
  collaborators_count: 2,
  created_at: '2024-01-15T10:00:00Z',
  updated_at: '2024-01-20T15:30:00Z'
};

const mockBranches = [
  {
    id: 1,
    name: 'main',
    repository: 1,
    repository_public_id: '550e8400-e29b-41d4-a716-446655440000',
    repository_name: 'Version Manager',
    is_default: true,
    is_repository_editable: true,
    created_at: '2024-01-15T10:00:00Z'
  },
  {
    id: 2,
    name: 'develop',
    repository: 1,
    repository_public_id: '550e8400-e29b-41d4-a716-446655440000',
    repository_name: 'Version Manager',
    is_default: false,
    is_repository_editable: true,
    created_at: '2024-01-16T11:00:00Z'
  },
  {
    id: 3,
    name: 'feature/metrics',
    repository: 1,
    repository_public_id: '550e8400-e29b-41d4-a716-446655440000',
    repository_name: 'Version Manager',
    is_default: false,
    is_repository_editable: true,
    created_at: '2024-01-18T14:00:00Z'
  }
];

const generateMockCommits = (days = 30) => {
  const commits = [];
  const now = new Date();
  const authors = ['User #1', 'User #2', 'User #3', 'Developer Team'];
  
  // РЕАЛИСТИЧНЫЕ сообщения с расширениями файлов
  const messages = [
    'Fix: исправлена ошибка в app.ts и components.tsx',
    'Feat: добавлена поддержка в utils.js и helpers.py',
    'Refactor: переработан код в service.ts и handler.go',
    'Docs: обновлена документация в README.md и index.html',
    'Style: форматирование config.json и settings.yaml',
    'Test: добавлены тесты в spec.ts и test.py',
    'Build: обновлены зависимости в package.json и requirements.txt',
    'Perf: оптимизация worker.rs и processor.cpp',
    'CI: обновлена конфиг в .github/workflows и Dockerfile',
    'Chore: обновление vendor packages.php и gems.rb',
    'Update: migration в schema.sql и models.java',
    'Fix API: обновлены endpoints в api.ts и serializers.py',
    'UI: компоненты Button.vue и Modal.jsx',
    'Database: script в migration_001.sql и seed.py',
    'Security: патч в auth.cs и security.java',
    'Deploy: скрипты в deploy.sh и config.yml'
  ];
  
  const branchList = ['main', 'develop', 'feature/metrics'];
  const branchDistribution = {
    'main': 0.5,
    'develop': 0.35,
    'feature/metrics': 0.15
  };

  for (let i = 0; i < days; i++) {
    const date = new Date(now);
    date.setDate(date.getDate() - i);
    
    if (Math.random() > 0.3) {
      const commitCount = Math.floor(Math.random() * 4) + 1;
      
      for (let j = 0; j < commitCount; j++) {
        const commitDate = new Date(date);
        commitDate.setHours(Math.floor(Math.random() * 24), Math.floor(Math.random() * 60), 0);
        
        let selectedBranch = 'main';
        const rand = Math.random();
        if (rand < branchDistribution['main']) {
          selectedBranch = 'main';
        } else if (rand < branchDistribution['main'] + branchDistribution['develop']) {
          selectedBranch = 'develop';
        } else {
          selectedBranch = 'feature/metrics';
        }
        
        commits.push({
          hash: Math.random().toString(16).substr(2, 12),
          message: messages[Math.floor(Math.random() * messages.length)],
          branch: selectedBranch,
          files_count: Math.floor(Math.random() * 10) + 1,
          created_at: commitDate.toISOString(),
          updated_at: commitDate.toISOString(),
          pushed: Math.random() > 0.2,
          author: authors[Math.floor(Math.random() * authors.length)]
        });
      }
    }
  }
  
  return commits.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
};

/* ============ API CALLS ============ */

const loadData = async () => {
  try {
    loading.value = true;
    errorMessage.value = '';
    selectedBranch.value = '';

    repo.value = mockRepository;
    branches.value = mockBranches.map(b => b.name);
    commitsData.value = generateMockCommits(parseInt(period.value));

    /* 
    // Реальные API запросы (закомментированы):
    
    const repoRes = await apiClient.get(
      `/api/version_management/repositories/${repoId}/`
    );
    repo.value = repoRes.data || (repoRes.success ? repoRes.data : null);

    const branchesRes = await apiClient.get(
      `/api/version_management/repositories/${repoId}/branches/`
    );
    branches.value = Array.isArray(branchesRes) 
      ? branchesRes.map(b => b.name)
      : branchesRes.data?.map(b => b.name) || [];

    const commitsRes = await apiClient.get(
      `/api/version_management/repositories/${repoId}/commits/`
    );
    
    let commits = [];
    if (Array.isArray(commitsRes)) {
      commits = commitsRes;
    } else if (commitsRes.data) {
      commits = Array.isArray(commitsRes.data) ? commitsRes.data : commitsRes.data.results || [];
    }

    if (commits.length === 0) {
      commitsData.value = generateMockCommits(parseInt(period.value));
    } else {
      commitsData.value = commits;
    }
    */

  } catch (error) {
    console.error('Error loading data:', error);
    errorMessage.value = error.message;
    repo.value = mockRepository;
    branches.value = mockBranches.map(b => b.name);
    commitsData.value = generateMockCommits(parseInt(period.value));
  } finally {
    loading.value = false;
  }
};

const refreshMetrics = () => {
  loading.value = true;
  setTimeout(() => {
    loadData();
  }, 500);
};

onMounted(() => {
  loadData();
});
</script>

<style scoped>
.metrics-dashboard {
  padding: 20px;
  max-width: 1400px;
  margin: 0 auto;
}

.header {
  padding-bottom: 20px;
  border-bottom: 1px solid var(--bs-border-color);
}

.header h1 {
  margin: 0;
  font-weight: 700;
  font-size: 2rem;
  color: var(--bs-body-color);
}

.repo-info {
  display: flex;
  align-items: center;
  gap: 10px;
}

.badge-id {
  border: none;
  background: #dc2626;
  color: white;
  padding: 4px 8px;
  font-weight: 600;
  border-radius: 4px;
}

/* Toolbar Styling */
.toolbar {
  background: var(--bs-card-bg);
  border: 1px solid var(--bs-border-color);
  border-radius: 8px;
  padding: 12px 16px;
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.toolbar-content {
  display: flex;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: 20px;
}

.toolbar-left {
  display: flex;
  align-items: center;
  gap: 0;
}

.filter-group {
  display: flex;
  flex-direction: column;
  gap: 4px;
  padding: 0 12px;
}

.filter-label {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: var(--bs-body-color);
  opacity: 0.7;
}

.filter-select {
  background: var(--bs-body-bg);
  border: 1px solid var(--bs-border-color);
  border-radius: 4px;
  padding: 6px 10px;
  font-size: 0.9rem;
  color: var(--bs-body-color);
  cursor: pointer;
  transition: all 0.2s;
  min-width: 110px;
}

.filter-select:hover {
  border-color: #3b82f6;
}

.filter-select:focus {
  outline: none;
  border-color: #3b82f6;
  box-shadow: 0 0 0 2px rgba(59, 130, 246, 0.1);
}

.filter-divider {
  width: 1px;
  height: 40px;
  background: var(--bs-border-color);
  opacity: 0.3;
  margin: 0 4px;
}

.btn-refresh {
  display: flex;
  align-items: center;
  gap: 8px;
  background: linear-gradient(135deg, #dc2626 0%, #b91c1c 100%);
  color: white;
  border: none;
  border-radius: 6px;
  padding: 8px 16px;
  font-size: 0.9rem;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 2px 8px rgba(220, 38, 38, 0.2);
}

.btn-refresh:hover:not(.loading) {
  transform: translateY(-2px);
  box-shadow: 0 4px 12px rgba(220, 38, 38, 0.3);
}

.btn-refresh:active {
  transform: translateY(0);
}

.btn-refresh.loading {
  opacity: 0.7;
  pointer-events: none;
}

.refresh-icon {
  display: inline-block;
  transition: transform 0.3s;
  font-size: 1rem;
}

.btn-refresh.loading .refresh-icon {
  animation: spin 1s linear infinite;
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.refresh-text {
  white-space: nowrap;
}

/* Light theme */
[data-bs-theme="light"] .filter-select {
  background: #f5f5f5;
  border-color: #d0d0d0;
  color: #333;
}

[data-bs-theme="light"] .filter-select:hover {
  border-color: #3b82f6;
  background: #fff;
}
</style>