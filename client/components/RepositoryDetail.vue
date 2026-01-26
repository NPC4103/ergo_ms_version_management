<template>
  <div class="repository-detail-page" v-if="repo">
    <!-- Header -->
    <div class="header d-flex justify-content-between align-items-center mb-4">
      <div class="d-flex align-items-center">
        <router-link :to="{ name: 'RepositoryList' }" class="btn btn-outline-secondary back-btn me-3 d-flex align-items-center">
            <ArrowLeft :size="16" class="me-2" /> Назад
        </router-link>
        <h1 id="repo-title">{{ repo.name }}</h1>
        <span class="badge badge-public ms-2">Public</span>
      </div>
    </div>

    <!-- Toolbar Panel -->
    <div class="toolbar-panel card mb-3 d-flex justify-content-between align-items-center">
      <div class="d-flex align-items-center gap-3">
        <!-- Branch Selector -->
        <div class="dropdown">
          <button class="btn btn-outline-secondary dropdown-toggle d-flex align-items-center gap-2" type="button" data-bs-toggle="dropdown">
            <GitBranch :size="14" />
            {{ currentBranch }}
          </button>
          <ul class="dropdown-menu custom-dropdown">
            <li v-for="branch in branches" :key="branch.name">
              <a class="dropdown-item" href="#" @click.prevent="selectBranch(branch.name)">{{ branch.name }}</a>
            </li>
          </ul>
        </div>
        <span class="branch-stats">{{ branches.length }} Branch · 0 Tags</span>
      </div>

      <div class="d-flex gap-2 position-relative">
         

           <!-- Releases Menu -->
           <div class="releases-menu" ref="releasesMenu">
                <button class="btn btn-warning d-flex align-items-center gap-2" @click="toggleReleases">
                    <ChevronDown :size="14" class="chevron-icon" :class="{ 'rotated': showReleases }" />
                    Релизы
                </button>
                <transition name="dropdown-anim">
                     <div class="actions-dropdown releases-dropdown-content" v-if="showReleases">
                        <div class="releases-header">
                            <h6>Релизы</h6>
                        </div>
                        <div class="releases-list" v-if="releases.length > 0">
                             <div v-for="release in releases" :key="release.id" class="release-item">
                                <div class="release-info">
                                     <span class="release-tag">{{ release.tag_name }}</span>
                                     <span class="release-date">{{ formatDate(release.created_at) }}</span>
                                </div>
                                <div class="release-actions">
                                    <button class="btn btn-sm btn-outline-secondary" @click="downloadRelease(release.zip_url)"><Download :size="14" /></button>
                                </div>
                             </div>
                        </div>
                        <div class="empty-releases text-center p-3" v-else>Нет релизов</div>
                        <div class="releases-footer">
                            <button class="btn btn-warning w-100 btn-sm" @click="openCreateReleaseModal">Создать релиз</button>
                        </div>
                    </div>
                </transition>
           </div>

          <!-- Actions Menu -->
          <div class="actions-menu" ref="actionsMenu">
            <button class="btn btn-success d-flex align-items-center gap-2" @click="toggleActionsMenu">
                <ChevronDown :size="14" class="chevron-icon" :class="{ 'rotated': showActionsMenu }" />
                Действия
            </button>
            <transition name="dropdown-anim">
                <div class="actions-dropdown" v-if="showActionsMenu" @click.stop>
                  <div class="actions-content" :class="{ blurred: activeSubmenu }">
                    <div class="action-item" @click="openSubmenu('files')">
                        <span class="d-flex align-items-center gap-2"><Folder :size="16" /> Файлы</span>
                        <span class="arrow">›</span>
                    </div>
                    <div class="action-item" @click="showCommitsModal = true; closeMenu()">
                        <span class="d-flex align-items-center gap-2"><History :size="16" /> Коммиты</span>
                    </div>
                    <div class="action-item" @click="copyCloneUrl">
                        <span class="d-flex align-items-center gap-2"><Link :size="16" /> Копировать ссылку</span>
                    </div>
                    <div class="action-item" @click="goToSettings">
                        <span class="d-flex align-items-center gap-2"><Settings :size="16" /> Настройки</span>
                    </div>
                  </div>
    
                  <!-- Submenu Files -->
                  <div class="submenu" :class="{ visible: activeSubmenu === 'files' }">
                    <div class="submenu-header" @click="closeSubmenu">‹ Файлы</div>
                    <div class="action-item" @click="createNewFile">
                        <span class="d-flex align-items-center gap-2"><FilePlus :size="16" /> Создать файл</span>
                    </div>
                    <div class="action-item" @click="uploadFile">
                        <span class="d-flex align-items-center gap-2"><Upload :size="16" /> Загрузить файл</span>
                    </div>
                  </div>
                </div>
            </transition>
          </div>
      </div>
    </div>

    <!-- Stats Card -->
    <div class="stats-card card mb-3">
      <div class="stats-container">
        <router-link :to="{ name: 'MetricsDashboard', params: { id: repo.id } }" class="stat-item stat-metrics">
          <div class="stat-icon">
            <BarChart3 :size="20" />
          </div>
          <div class="stat-content">
            <div class="stat-label">Метрики репозитория</div>
            <div class="stat-value">Перейти →</div>
          </div>
        </router-link>

        <div class="stat-divider"></div>

        <div class="stat-item">
          <div class="stat-icon">
            <History :size="20" />
          </div>
          <div class="stat-content">
            <div class="stat-label">Всего коммитов</div>
            <div class="stat-value">{{ commits.length || 0 }}</div>
          </div>
        </div>

        <div class="stat-divider"></div>

        <div class="stat-item">
          <div class="stat-icon">
            <GitBranch :size="20" />
          </div>
          <div class="stat-content">
            <div class="stat-label">Активных веток</div>
            <div class="stat-value">{{ branches.length }}</div>
          </div>
        </div>

        <div class="stat-divider"></div>

        <div class="stat-item">
          <div class="stat-icon">
            <FileText :size="20" />
          </div>
          <div class="stat-content">
            <div class="stat-label">Файлов в репо</div>
            <div class="stat-value">{{ files.length }}</div>
          </div>
        </div>
      </div>
    </div>

    <!-- File Manager -->
    <div class="scroll-wrapper card">
      <div class="scroll-red-bar"></div>
      <div class="scroll-body" :class="{ expanded: isExpanded }">
        <div class="files-container" :class="{ 'visible': isExpanded }">
          <!-- File List -->
          <div v-for="(item, index) in sortedFiles" :key="item.name" class="file-row"
               :style="{ transitionDelay: `${index * 0.05}s` }">
            <div class="file-name">
                <Folder v-if="item.type === 'dir'" :size="16" class="text-warning" />
                <FileText v-else :size="16" class="file-icon" />
                {{ item.name }}
            </div>
            <div class="file-commit text-muted">{{ item.last_message || '' }}</div>
            <div class="file-date text-muted">{{ item.last_date || '' }}</div>
          </div>
          
          <!-- Empty State -->
          <div v-if="files.length === 0" class="empty-state d-flex flex-column align-items-center justify-content-center">
            <FolderOpen :size="48" class="mb-3 empty-icon" />
            <p class="mb-3 empty-text-content">Репозиторий пуст</p>
            <button class="btn btn-outline-secondary btn-sm" @click="createNewFile">Добавить файл</button>
          </div>
        </div>
      </div>
      <div class="scroll-red-bar"></div>
    </div>
    
    <div class="toggle-wrapper">
      <div class="toggle-btn" @click="toggleScroll" :class="{ rotated: isExpanded }">
        <ChevronDown :size="16" color="white" />
      </div>
    </div>

    <!-- Modals -->
    <div class="modal-overlay" v-if="showCommitsModal" @click.self="showCommitsModal = false">
      <div class="modal-container">
        <div class="modal-header">
          <h4>История коммитов</h4>
          <button class="modal-close" @click="showCommitsModal = false"><X :size="24" /></button>
        </div>
        <div class="modal-body">
          <div class="d-flex justify-content-end mb-3">
            <router-link :to="{ name: 'CommitCreate', params: { id: repo.id } }" class="btn btn-primary btn-sm">Создать коммит</router-link>
          </div>
          <CommitList :repoId="repo.id" />
        </div>
      </div>
    </div>

    <!-- Create Release Modal -->
    <div class="modal-overlay" v-if="showCreateReleaseModal" @click.self="closeCreateReleaseModal">
        <div class="modal-container">
            <div class="modal-header">
                <h4>Создание релиза</h4>
                <button class="modal-close" @click="closeCreateReleaseModal"><X :size="24" /></button>
            </div>
            <div class="modal-body">
                <input type="text" class="form-control mb-3 bg-dark text-white border-secondary" v-model="newRelease.tag_name" placeholder="v1.0.0">
                <input type="text" class="form-control mb-3 bg-dark text-white border-secondary" v-model="newRelease.name" placeholder="Название">
                <textarea class="form-control mb-3 bg-dark text-white border-secondary" rows="4" v-model="newRelease.body" placeholder="Описание"></textarea>
                <button class="btn btn-warning w-100" @click="createRelease">Опубликовать</button>
            </div>
        </div>
    </div>

  </div>
  <div v-else-if="loading" class="p-4 text-center">Загрузка...</div>
  <div v-else class="p-4 text-center text-danger">Репозиторий не найден</div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints.js';
import { useToast } from 'vue-toastification';
import CommitList from './CommitList.vue';
import { 
    ArrowLeft, GitBranch, Folder, FileText, History, Link, Settings, 
    FilePlus, Upload, ChevronDown, FolderOpen, X, Tag, Download, BarChart3
} from 'lucide-vue-next';

const route = useRoute();
const router = useRouter();
const toast = useToast();

const repoId = route.params.id;
const repo = ref(null);
const loading = ref(true);
const isExpanded = ref(false);

// Menus
const showActionsMenu = ref(false);
const showReleases = ref(false);
const activeSubmenu = ref(null);
const actionsMenu = ref(null);
const releasesMenu = ref(null);

// Modals
const showCommitsModal = ref(false);
const showCreateReleaseModal = ref(false);

const branches = ref([{ name: 'main' }]);
const currentBranch = ref('main');
const files = ref([]); 
const commits = ref([]);
const releases = ref([]);
const newRelease = ref({ tag_name: '', name: '', body: '' });

const sortedFiles = computed(() => [...files.value].sort((a, b) => {
  if (a.type === 'dir' && b.type !== 'dir') return -1;
  if (a.type !== 'dir' && b.type === 'dir') return 1;
  return a.name.localeCompare(b.name);
}));

const toggleActionsMenu = () => { showActionsMenu.value = !showActionsMenu.value; showReleases.value = false; activeSubmenu.value = null; };
const toggleReleases = () => { showReleases.value = !showReleases.value; showActionsMenu.value = false; };
const openSubmenu = (n) => { activeSubmenu.value = n; };
const closeSubmenu = () => { activeSubmenu.value = null; };
const closeMenu = () => { showActionsMenu.value = false; showReleases.value = false; activeSubmenu.value = null; };
const toggleScroll = () => { isExpanded.value = !isExpanded.value; };
const selectBranch = (n) => { currentBranch.value = n; };
const copyCloneUrl = () => { navigator.clipboard.writeText(`${window.location.origin}/git/${repo.value?.name}.git`); toast.success('Ссылка скопирована!'); closeMenu(); };
const createNewFile = () => { toast.info('Создание файла...'); closeMenu(); };
const uploadFile = () => { toast.info('Загрузка файлов...'); closeMenu(); };
const goToSettings = () => { closeMenu(); router.push({ name: 'RepositorySettings', params: { id: repoId } }); };

// Releases
const openCreateReleaseModal = () => { showCreateReleaseModal.value = true; closeMenu(); };
const closeCreateReleaseModal = () => { showCreateReleaseModal.value = false; };
const createRelease = () => {
    releases.value.unshift({ id: Date.now(), ...newRelease.value, created_at: new Date().toISOString() });
    closeCreateReleaseModal();
    newRelease.value = { tag_name: '', name: '', body: '' };
    toast.success('Релиз создан');
};
const formatDate = (d) => new Date(d).toLocaleDateString();
const downloadRelease = () => toast.info('Скачивание...');

const handleClickOutside = (e) => {
    if (actionsMenu.value && !actionsMenu.value.contains(e.target)) showActionsMenu.value = false;
    if (releasesMenu.value && !releasesMenu.value.contains(e.target)) showReleases.value = false;
};

onMounted(() => { document.addEventListener('click', handleClickOutside); loadRepo(); });
onUnmounted(() => { document.removeEventListener('click', handleClickOutside); });

const loadRepo = async () => {
  loading.value = true;
  try {
    const response = await apiClient.get(versionManagementEndpoints.repositories.retrieve(repoId));
    if (response.success) repo.value = response.data;
    else toast.error(response.message || 'Ошибка загрузки');
  } catch (e) { toast.error('Ошибка сети'); console.error(e); }
  finally { loading.value = false; }
};
</script>

<style scoped>
/* Page Layout */
.repository-detail-page { padding: 20px; max-width: 1000px; margin: 0 auto; }
h1 { margin: 0; }

/* Light theme overrides - black borders and text */
[data-bs-theme="light"] .toolbar-panel .btn-outline-secondary {
    border-color: #333 !important;
    color: #333 !important;
}
[data-bs-theme="light"] .toolbar-panel .btn-outline-secondary:hover {
    background-color: #333 !important;
    color: #fff !important;
}
[data-bs-theme="light"] .branch-stats {
    color: #333 !important;
}
[data-bs-theme="light"] .empty-state .btn-outline-secondary {
    border-color: #333 !important;
    color: #333 !important;
}
[data-bs-theme="light"] .empty-text-content {
    color: #333 !important;
}
[data-bs-theme="light"] .empty-icon {
    color: #555 !important;
}
[data-bs-theme="light"] .back-btn {
    border-color: #333 !important;
    color: #333 !important;
}

/* Back Button */
.back-btn {
    font-weight: 600;
    transition: all 0.2s;
}
.back-btn:hover {
    background-color: #dc2626 !important;
    color: #ffffff !important;
    border-color: #dc2626 !important;
}

/* Metrics Button */
.btn-info {
    background-color: #3b82f6 !important;
    border-color: #3b82f6 !important;
    color: #ffffff !important;
    font-weight: 500;
    transition: all 0.2s;
}
.btn-info:hover {
    background-color: #2563eb !important;
    border-color: #2563eb !important;
    color: #ffffff !important;
}

/* Public Badge */
.badge-public {
    background-color: #dc2626 !important;
    color: #ffffff;
    font-weight: 500;
}

/* Toolbar Panel - uses .card class for background */
.toolbar-panel { 
    display: flex !important; 
    flex-direction: row !important;
    justify-content: space-between !important; 
    align-items: center !important; 
    padding: 12px 20px !important; 
    border-radius: 8px; 
}
.branch-stats {
    font-size: 0.9rem;
}

/* Dropdowns - inherit card background */
.custom-dropdown, .actions-dropdown { 
    background-color: var(--bs-card-bg) !important; 
    border: 1px solid var(--bs-border-color) !important;
}
.dropdown-item, .action-item { 
    display: flex; align-items: center; justify-content: space-between; padding: 8px 16px; cursor: pointer; 
}
.dropdown-item:hover, .action-item:hover { 
    background: var(--bs-tertiary-bg) !important; 
}

/* Menus & Animations */
.actions-menu, .releases-menu { position: relative; }
.actions-dropdown { 
    position: absolute; 
    top: 100%; 
    right: 0; 
    margin-top: 8px; 
    min-width: 240px; 
    border-radius: 8px; 
    box-shadow: 0 8px 32px rgba(0,0,0,0.15); 
    overflow: hidden; 
    z-index: 1000; 
    transform-origin: top center;
}

/* Vue Transition 'dropdown-anim' */
.dropdown-anim-enter-active,
.dropdown-anim-leave-active {
  transition: all 0.3s cubic-bezier(0.25, 0.8, 0.25, 1);
  max-height: 500px;
  opacity: 1;
  transform: translateY(0);
}

.dropdown-anim-enter-from,
.dropdown-anim-leave-to {
  max-height: 0;
  opacity: 0;
  transform: translateY(-10px);
}

.releases-header, .submenu-header { padding: 12px 16px; border-bottom: 1px solid var(--bs-border-color); font-size: 0.9rem; }
.releases-footer { padding: 10px; border-top: 1px solid var(--bs-border-color); }
.release-item { padding: 10px 16px; border-bottom: 1px solid var(--bs-border-color); display: flex; justify-content: space-between; align-items: center; }
.release-item:hover { background: var(--bs-tertiary-bg); }
.release-tag { color: #f59e0b; font-weight: bold; margin-right: 10px; }
.release-date { font-size: 0.8rem; }

/* Submenu */
.submenu { position: absolute; inset: 0; background-color: var(--bs-card-bg) !important; transform: translateX(100%); transition: transform 0.3s; z-index: 10; }
.submenu.visible { transform: translateX(0); }

/* Chevron Rotation & Position */
.chevron-icon {
    transition: transform 0.3s ease;
}
.chevron-icon.rotated {
    transform: rotate(180deg);
}
.toggle-btn svg { transition: transform 0.3s; }
.toggle-btn.rotated svg { transform: rotate(180deg); }


/* Scroll Wrapper - uses .card class for background */
.scroll-wrapper { 
    border-radius: 8px; 
    overflow: hidden; 
    margin-top: 20px; 
    padding: 0 !important;
}
.scroll-red-bar { 
    height: 5px; 
    background-color: #dc2626; 
}
.scroll-body { max-height: 0; overflow: hidden; transition: max-height 0.6s cubic-bezier(0.25, 0.8, 0.25, 1); }
.scroll-body.expanded { max-height: 500px; }
.files-container { min-height: 200px; opacity: 0; transform: translateY(-20px); transition: opacity 0.5s ease, transform 0.5s ease; }
.files-container.visible { opacity: 1; transform: translateY(0); }

/* Empty State */
.empty-state { padding: 40px; text-align: center; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100%; transition: opacity 0.5s ease; }
.empty-icon { opacity: 0.5; } 

.file-row { 
    display: grid; grid-template-columns: 2fr 3fr 1fr; gap: 15px; padding: 10px 15px; border-bottom: 1px solid var(--bs-border-color); cursor: pointer; align-items: center; 
    opacity: 0; transform: translateY(10px); animation: fadeInRow 0.5s forwards ease-out;
}
.file-row:hover { background: var(--bs-tertiary-bg); }
@keyframes fadeInRow {
    to { opacity: 1; transform: translateY(0); }
}

.file-name { display: flex; align-items: center; gap: 10px; }
.toggle-wrapper { display: flex; justify-content: center; }
.toggle-btn { 
    width: 40px; 
    height: 20px; 
    background-color: #dc2626; 
    display: flex; 
    align-items: center; 
    justify-content: center; 
    cursor: pointer; 
    border-radius: 0 0 6px 6px; 
    box-shadow: 0 4px 12px rgba(220,38,38,0.4); 
}

/* Modal */
.modal-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.7); display: flex; align-items: center; justify-content: center; z-index: 2000; }
.modal-container { background: var(--bs-card-bg); border: 1px solid #dc2626; border-radius: 12px; width: 90%; max-width: 700px; max-height: 80vh; overflow: hidden; display: flex; flex-direction: column; }
.modal-header { display: flex; justify-content: space-between; align-items: center; padding: 16px 20px; border-bottom: 1px solid var(--bs-border-color); }
.modal-close { background: none; border: none; cursor: pointer; }
.modal-close:hover { opacity: 0.7; }
.modal-body { padding: 20px; overflow-y: auto; }

/* Stats Card */
.stats-card {
    border: none !important;
    background: var(--bs-card-bg);
    padding: 16px 20px !important;
    border-radius: 8px;
}

.stats-container {
    display: flex;
    align-items: center;
    gap: 0;
    justify-content: space-around;
}

.stat-item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    border-radius: 6px;
    cursor: pointer;
    transition: all 0.2s ease;
    text-decoration: none;
    color: inherit;
    flex: 1;
}

.stat-item:hover {
    background: var(--bs-tertiary-bg);
    transform: translateY(-2px);
}

.stat-metrics {
    background: linear-gradient(135deg, rgba(59, 130, 246, 0.1) 0%, rgba(139, 92, 246, 0.1) 100%);
}

.stat-metrics:hover {
    background: linear-gradient(135deg, rgba(59, 130, 246, 0.2) 0%, rgba(139, 92, 246, 0.2) 100%);
}

.stat-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 40px;
    height: 40px;
    border-radius: 6px;
    background: rgba(59, 130, 246, 0.15);
    color: #3b82f6;
    flex-shrink: 0;
}

.stat-metrics .stat-icon {
    background: rgba(59, 130, 246, 0.2);
    color: #3b82f6;
}

.stat-content {
    display: flex;
    flex-direction: column;
    gap: 4px;
}

.stat-label {
    font-size: 0.85rem;
    font-weight: 500;
    opacity: 0.7;
}

.stat-value {
    font-size: 1.2rem;
    font-weight: 600;
    color: #3b82f6;
}

.stat-divider {
    width: 1px;
    height: 40px;
    background: var(--bs-border-color);
    opacity: 0.3;
}

/* Light theme stats card */
[data-bs-theme="light"] .stat-item:hover {
    background: #f0f0f0;
}

[data-bs-theme="light"] .stat-metrics {
    background: linear-gradient(135deg, rgba(59, 130, 246, 0.08) 0%, rgba(139, 92, 246, 0.08) 100%);
}

[data-bs-theme="light"] .stat-metrics:hover {
    background: linear-gradient(135deg, rgba(59, 130, 246, 0.15) 0%, rgba(139, 92, 246, 0.15) 100%);
}
</style>
