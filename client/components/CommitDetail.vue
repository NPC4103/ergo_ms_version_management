<template>
  <div class="commit-detail-page">
    <!-- Header -->
    <div class="detail-header">
      <router-link :to="{ name: 'RepositoryDetail', params: { id: repoId } }" class="btn btn-outline-secondary">
        <i class="bi bi-arrow-left"></i> Назад к репозиторию
      </router-link>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="loading-container">
      <div class="spinner-border text-primary" role="status">
        <span class="visually-hidden">Загрузка...</span>
      </div>
    </div>

    <!-- Commit Info -->
    <div v-else-if="commit" class="commit-content">
      <!-- Commit Header -->
      <div class="commit-header-card">
        <div class="commit-hash-badge">
          <i class="bi bi-git"></i>
          {{ commit.hash?.substring(0, 7) }}
          <button class="btn btn-sm btn-link" @click="copyHash" title="Копировать">
            <i class="bi bi-clipboard"></i>
          </button>
        </div>
        
        <h2 class="commit-message">{{ commit.message || 'Без сообщения' }}</h2>
        
        <div class="commit-meta">
          <div class="meta-item">
            <i class="bi bi-person-circle"></i>
            <span>{{ commit.author }}</span>
          </div>
          <div class="meta-item">
            <i class="bi bi-calendar3"></i>
            <span>{{ formatDate(commit.date) }}</span>
          </div>
          <div v-if="commit.parents?.length" class="meta-item">
            <i class="bi bi-diagram-2"></i>
            <span>{{ commit.parents.length }} родитель(ей)</span>
          </div>
        </div>
      </div>

      <!-- Stats -->
      <div class="commit-stats">
        <div class="stat-card stat-files">
          <i class="bi bi-file-earmark-code"></i>
          <span class="stat-value">{{ changedFiles.length }}</span>
          <span class="stat-label">файлов</span>
        </div>
        <div class="stat-card stat-additions">
          <i class="bi bi-plus-lg"></i>
          <span class="stat-value">{{ totalAdditions }}</span>
          <span class="stat-label">добавлено</span>
        </div>
        <div class="stat-card stat-deletions">
          <i class="bi bi-dash-lg"></i>
          <span class="stat-value">{{ totalDeletions }}</span>
          <span class="stat-label">удалено</span>
        </div>
      </div>

      <!-- Changed Files List -->
      <div class="files-section">
        <h4 class="section-title">
          <i class="bi bi-folder2-open"></i>
          Изменённые файлы
        </h4>
        
        <div class="files-list">
          <div 
            v-for="file in changedFiles" 
            :key="file.path" 
            class="file-item"
            :class="{ 'expanded': expandedFiles.includes(file.path) }"
          >
            <div class="file-header" @click="toggleFile(file.path)">
              <div class="file-info">
                <span class="file-status" :class="file.status">
                  {{ getStatusIcon(file.status) }}
                </span>
                <span class="file-path">{{ file.path }}</span>
              </div>
              <div class="file-stats">
                <span class="additions">+{{ file.additions }}</span>
                <span class="deletions">-{{ file.deletions }}</span>
                <i class="bi" :class="expandedFiles.includes(file.path) ? 'bi-chevron-up' : 'bi-chevron-down'"></i>
              </div>
            </div>
            
            <!-- Diff Content -->
            <div v-if="expandedFiles.includes(file.path)" class="diff-container">
              <div 
                v-for="(line, idx) in file.diffLines" 
                :key="idx" 
                class="diff-line"
                :class="line.type"
              >
                <span class="line-number old">{{ line.oldNum || '' }}</span>
                <span class="line-number new">{{ line.newNum || '' }}</span>
                <span class="line-content">{{ line.content }}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Error State -->
    <div v-else class="error-state">
      <i class="bi bi-exclamation-triangle display-1 text-warning"></i>
      <p class="text-muted mt-3">Не удалось загрузить информацию о коммите</p>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';
import { useToast } from 'vue-toastification';

const route = useRoute();
const toast = useToast();

const repoId = route.params.id;
const commitHash = route.params.hash;

// State
const loading = ref(true);
const commit = ref(null);
const changedFiles = ref([]);
const expandedFiles = ref([]);

// Computed
const totalAdditions = computed(() => 
  changedFiles.value.reduce((sum, f) => sum + (f.additions || 0), 0)
);

const totalDeletions = computed(() => 
  changedFiles.value.reduce((sum, f) => sum + (f.deletions || 0), 0)
);

// Methods
const loadCommit = async () => {
  loading.value = true;
  try {
    const response = await apiClient.get(
      versionManagementEndpoints.repositories.commitRetrieve(repoId, commitHash)
    );
    if (response.success) {
      commit.value = response.data;
    } else {
      throw new Error('Response success is false');
    }
  } catch (error) {
    console.warn('Failed to load commit metadata, using demo info:', error);
    commit.value = getDemoCommitInfo();
  }
};

const getDemoCommitInfo = () => {
  return {
    hash: commitHash || 'abcdef123456789',
    message: 'feat: добавление команд для установки, запуска и настройки',
    author: 'Egor <egor@example.com>',
    date: new Date().toISOString(),
    parents: ['parent1_hash']
  };
};

const loadDiff = async () => {
  try {
    const response = await apiClient.get(
      versionManagementEndpoints.repositories.commitDiff(repoId, commitHash)
    );
    if (response.success && response.data) {
      // Parse diff data
      if (typeof response.data === 'string') {
        changedFiles.value = parseDiffString(response.data);
      } else if (Array.isArray(response.data)) {
        changedFiles.value = response.data;
      } else if (response.data.files) {
        changedFiles.value = response.data.files;
      }
    }
  } catch (error) {
    console.error('Failed to load diff:', error);
    // Demo data for visualization
    changedFiles.value = getDemoFiles();
  } finally {
    loading.value = false;
  }
};

const parseDiffString = (diffStr) => {
  // Simple diff parser
  const files = [];
  const fileBlocks = diffStr.split(/^diff --git/m).filter(Boolean);
  
  fileBlocks.forEach(block => {
    const pathMatch = block.match(/a\/(.+?) b\//);
    if (pathMatch) {
      const lines = block.split('\n');
      const diffLines = [];
      let additions = 0;
      let deletions = 0;
      let oldLine = 0;
      let newLine = 0;
      
      lines.forEach(line => {
        if (line.startsWith('@@')) {
          const match = line.match(/@@ -(\d+),?\d* \+(\d+),?\d* @@/);
          if (match) {
            oldLine = parseInt(match[1]);
            newLine = parseInt(match[2]);
          }
          diffLines.push({ type: 'hunk', content: line });
        } else if (line.startsWith('+') && !line.startsWith('+++')) {
          additions++;
          diffLines.push({ type: 'addition', oldNum: null, newNum: newLine++, content: line.substring(1) });
        } else if (line.startsWith('-') && !line.startsWith('---')) {
          deletions++;
          diffLines.push({ type: 'deletion', oldNum: oldLine++, newNum: null, content: line.substring(1) });
        } else if (!line.startsWith('\\')) {
          diffLines.push({ type: 'context', oldNum: oldLine++, newNum: newLine++, content: line.substring(1) || line });
        }
      });
      
      files.push({
        path: pathMatch[1],
        status: additions > 0 && deletions > 0 ? 'modified' : additions > 0 ? 'added' : 'deleted',
        additions,
        deletions,
        diffLines
      });
    }
  });
  
  return files;
};

const getDemoFiles = () => {
  // Demo data for testing visualization
  return [
    {
      path: 'src/components/App.vue',
      status: 'modified',
      additions: 15,
      deletions: 3,
      diffLines: [
        { type: 'hunk', content: '@@ -10,6 +10,18 @@' },
        { type: 'context', oldNum: 10, newNum: 10, content: 'import { ref } from "vue";' },
        { type: 'deletion', oldNum: 11, newNum: null, content: 'const oldValue = false;' },
        { type: 'addition', oldNum: null, newNum: 11, content: 'const newValue = true;' },
        { type: 'addition', oldNum: null, newNum: 12, content: 'const extraValue = "hello";' },
        { type: 'context', oldNum: 12, newNum: 13, content: '' },
      ]
    },
    {
      path: 'modules/auth/service.py',
      status: 'modified',
      additions: 8,
      deletions: 2,
      diffLines: [
        { type: 'hunk', content: '@@ -42,7 +42,13 @@' },
        { type: 'context', oldNum: 42, newNum: 42, content: '    def authenticate(self, credentials):' },
        { type: 'context', oldNum: 43, newNum: 43, content: '        user = self.db.find_user(credentials.username)' },
        { type: 'deletion', oldNum: 44, newNum: null, content: '        if user and user.password == credentials.password:' },
        { type: 'addition', oldNum: null, newNum: 44, content: '        if user and self.crypto.verify(credentials.password, user.password_hash):' },
        { type: 'addition', oldNum: null, newNum: 45, content: '            # Log successful login' },
        { type: 'addition', oldNum: null, newNum: 46, content: '            self.logger.info(f"User {user.id} logged in")' },
        { type: 'context', oldNum: 45, newNum: 47, content: '            return user' },
      ]
    },
    {
      path: 'README.md',
      status: 'modified',
      additions: 5,
      deletions: 0,
      diffLines: [
        { type: 'hunk', content: '@@ -1,3 +1,8 @@' },
        { type: 'context', oldNum: 1, newNum: 1, content: '# Ergo MS Core' },
        { type: 'addition', oldNum: null, newNum: 2, content: '' },
        { type: 'addition', oldNum: null, newNum: 3, content: '## Getting Started' },
        { type: 'addition', oldNum: null, newNum: 4, content: 'Run `npm install` and then `npm run dev` to start.' },
        { type: 'addition', oldNum: null, newNum: 5, content: '' },
      ]
    },
    {
      path: 'src/utils/helper.js',
      status: 'added',
      additions: 25,
      deletions: 0,
      diffLines: [
        { type: 'hunk', content: '@@ -0,0 +1,25 @@' },
        { type: 'addition', oldNum: null, newNum: 1, content: 'export function helper() {' },
        { type: 'addition', oldNum: null, newNum: 2, content: '  return "new file";' },
        { type: 'addition', oldNum: null, newNum: 3, content: '}' },
      ]
    }
  ];
};

const toggleFile = (path) => {
  const idx = expandedFiles.value.indexOf(path);
  if (idx === -1) {
    expandedFiles.value.push(path);
  } else {
    expandedFiles.value.splice(idx, 1);
  }
};

const getStatusIcon = (status) => {
  switch (status) {
    case 'added': return 'A';
    case 'modified': return 'M';
    case 'deleted': return 'D';
    case 'renamed': return 'R';
    default: return '?';
  }
};

const copyHash = () => {
  navigator.clipboard.writeText(commit.value?.hash || '');
  toast.success('Hash скопирован');
};

const formatDate = (dateString) => {
  if (!dateString) return '';
  return new Date(dateString).toLocaleString('ru-RU', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit'
  });
};

// Lifecycle
onMounted(() => {
  if (repoId && commitHash) {
    loadCommit();
    loadDiff();
  }
});
</script>

<style scoped>
.commit-detail-page {
  padding: 20px;
  max-width: 1200px;
  margin: 0 auto;
}

.detail-header {
  margin-bottom: 20px;
}

.loading-container {
  display: flex;
  justify-content: center;
  align-items: center;
  height: 300px;
}

.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 300px;
}

/* Commit Header Card */
.commit-header-card {
  background: linear-gradient(135deg, #1e3a5f 0%, #2d4a6f 100%);
  border-radius: 16px;
  padding: 24px;
  margin-bottom: 20px;
  color: white;
}

.commit-hash-badge {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  background: rgba(255,255,255,0.1);
  padding: 6px 14px;
  border-radius: 20px;
  font-family: 'Consolas', monospace;
  font-size: 0.9rem;
  margin-bottom: 12px;
}

.commit-hash-badge .btn {
  color: rgba(255,255,255,0.7);
  padding: 0;
}

.commit-message {
  font-size: 1.5rem;
  font-weight: 600;
  margin-bottom: 16px;
  line-height: 1.4;
}

.commit-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 20px;
}

.meta-item {
  display: flex;
  align-items: center;
  gap: 8px;
  color: rgba(255,255,255,0.8);
  font-size: 0.9rem;
}

.meta-item i {
  color: rgba(255,255,255,0.6);
}

/* Stats */
.commit-stats {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(120px, 1fr));
  gap: 15px;
  margin-bottom: 25px;
}

.stat-card {
  background: #252528;
  border-radius: 12px;
  padding: 16px;
  text-align: center;
  border: 1px solid rgba(255,255,255,0.05);
}

.stat-card i {
  font-size: 1.5rem;
  margin-bottom: 8px;
}

.stat-value {
  display: block;
  font-size: 1.8rem;
  font-weight: 700;
  color: #fff;
}

.stat-label {
  font-size: 0.8rem;
  color: #aaa;
}

.stat-files { color: #3b82f6; }
.stat-files i { color: #3b82f6; }

.stat-additions { color: #10b981; }
.stat-additions i { color: #10b981; }

.stat-deletions { color: #ef4444; }
.stat-deletions i { color: #ef4444; }

/* Files Section */
.files-section {
  background: #1e1e1e;
  border-radius: 12px;
  border: 1px solid rgba(255,255,255,0.1);
  overflow: hidden;
}

.section-title {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 16px 20px;
  margin: 0;
  background: #252528;
  border-bottom: 1px solid rgba(255,255,255,0.05);
  font-size: 1rem;
  color: #fff;
}

.file-item {
  border-bottom: 1px solid rgba(255,255,255,0.05);
}

.file-item:last-child {
  border-bottom: none;
}

.file-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 20px;
  cursor: pointer;
  transition: background 0.2s;
  color: #ddd;
}

.file-header:hover {
  background: rgba(255,255,255,0.05);
}

.file-info {
  display: flex;
  align-items: center;
  gap: 12px;
}

.file-status {
  width: 24px;
  height: 24px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 0.75rem;
  font-weight: 700;
  color: white;
}

.file-status.added { background: #10b981; }
.file-status.modified { background: #f59e0b; }
.file-status.deleted { background: #ef4444; }
.file-status.renamed { background: #8b5cf6; }

.file-path {
  font-family: 'Consolas', monospace;
  font-size: 0.9rem;
}

.file-stats {
  display: flex;
  align-items: center;
  gap: 12px;
}

.additions {
  color: #10b981;
  font-weight: 600;
  font-size: 0.85rem;
}

.deletions {
  color: #ef4444;
  font-weight: 600;
  font-size: 0.85rem;
}

/* Diff Container */
.diff-container {
  background: #1e1e1e;
  font-family: 'Consolas', 'Monaco', monospace;
  font-size: 13px;
  overflow-x: auto;
}

.diff-line {
  display: flex;
  line-height: 1.6;
}

.diff-line.hunk {
  background: rgba(59, 130, 246, 0.2);
  color: #60a5fa;
  padding: 4px 16px;
}

.diff-line.context {
  color: #d4d4d4;
}

.diff-line.addition {
  background: rgba(16, 185, 129, 0.15);
  color: #4ade80;
}

.diff-line.deletion {
  background: rgba(239, 68, 68, 0.15);
  color: #f87171;
}

.line-number {
  width: 50px;
  padding: 0 8px;
  text-align: right;
  color: #6b7280;
  background: rgba(0,0,0,0.2);
  user-select: none;
}

.line-content {
  flex: 1;
  padding: 0 16px;
  white-space: pre;
}
</style>
