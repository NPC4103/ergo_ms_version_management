<template>
  <div class="repository-files-page" v-if="repo">
    <div class="header d-flex justify-content-between align-items-center mb-3">
        <div class="d-flex align-items-center">
            <router-link :to="{ name: 'RepositoryDetail', params: { id: repoId } }" class="btn btn-outline-secondary back-btn me-3 d-flex align-items-center">
                <ArrowLeft :size="16" />
            </router-link>
            <h5 class="m-0">Файлы: {{ repo.name }} <span class="text-muted">({{ currentBranch }})</span></h5>
        </div>
    </div>

    <div class="ide-container d-flex flex-grow-1"
         @dragover.prevent="dragActive = true" 
         @dragleave.prevent="dragActive = false" 
         @drop.prevent="handleDrop"
         :class="{ 'border-primary': dragActive }">
        <!-- Sidebar: File Tree -->
        <div class="sidebar border-end border-secondary p-0 d-flex flex-column" style="width: 300px; min-width: 250px;">
             <!-- Breadcrumbs (Mini) -->
             <div class="sidebar-header p-2 border-bottom">
                <div class="d-flex align-items-center flex-wrap gap-1 small font-monospace">
                    <span class="cursor-pointer hover-text-white" @click="navigateDir('')">ROOT</span>
                    <template v-for="(part, index) in currentPath.split('/').filter(Boolean)" :key="index">
                        <span class="text-muted">/</span>
                        <span class="cursor-pointer hover-text-white" @click="navigateDir(part, index)">{{ part }}</span>
                    </template>
                </div>
             </div>
             
             <!-- File List -->
             <div class="file-list flex-grow-1 overflow-auto p-2">
                <div v-if="loadingFiles" class="text-center text-muted mt-4">Загрузка...</div>
                <div v-else>
                    <div v-if="currentPath" class="file-item d-flex align-items-center p-1 rounded mb-1 text-muted" @click="goUp">
                         <Folder :size="14" class="me-2 text-warning" /> ..
                    </div>
                    
                    <div v-for="file in sortedFiles" :key="file.name" 
                         class="file-item d-flex align-items-center p-1 rounded mb-1 cursor-pointer"
                         :class="{'active': selectedFile && selectedFile.path === file.path}"
                         @click="handleFileClick(file)">
                        <component :is="file.type === 'dir' ? Folder : FileText" 
                                   :size="14" 
                                   class="me-2"
                                   :class="file.type === 'dir' ? 'text-warning' : 'text-info'" />
                        <span class="text-truncate small">{{ file.name }}</span>
                    </div>
                     <div v-if="sortedFiles.length === 0" class="text-center text-muted mt-2 small">Нет файлов</div>
                </div>
             </div>
        </div>

        <!-- Main Content: File Viewer -->
        <div class="main-content flex-grow-1 d-flex flex-column overflow-hidden">
            <div v-if="selectedFile && selectedFile.type !== 'dir'" class="h-100 d-flex flex-column">
                <div class="editor-header p-2 border-bottom d-flex justify-content-between align-items-center">
                    <span class="font-monospace small">{{ selectedFile.name }}</span>
                    <div class="d-flex gap-2">
                        <button class="btn btn-sm btn-outline-success" @click="saveFile">Сохранить</button>
                    </div>
                </div>
                <div class="editor-body flex-grow-1 position-relative">
                    <textarea class="form-control h-100 w-100 border-0 font-monospace p-3 editor-textarea" 
                              style="resize: none; outline: none;"
                              v-model="fileContent"></textarea>
                </div>
            </div>
            <div v-else class="h-100 d-flex flex-column align-items-center justify-content-center text-muted">
                <FileText :size="48" class="mb-3 opacity-25" />
                <p>Выберите файл для просмотра или перетащите файлы для загрузки</p>
            </div>
        </div>
    </div>

  </div>
  <div v-else-if="loading" class="p-4 text-center">Загрузка...</div>
</template>

<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints.js';
import { useToast } from 'vue-toastification';
import { ArrowLeft, Folder, FileText } from 'lucide-vue-next';

const route = useRoute();
const toast = useToast();
const repoId = route.params.id;

const repo = ref(null);
const branches = ref([]);
const currentBranch = ref('main');
const currentPath = ref('');
const files = ref([]);
const loading = ref(true);
const loadingFiles = ref(false);
const dragActive = ref(false);

const selectedFile = ref(null); // File object
const fileContent = ref('');

const sortedFiles = computed(() => [...files.value].sort((a, b) => {
    if (a.type === 'dir' && b.type !== 'dir') return -1;
    if (a.type !== 'dir' && b.type === 'dir') return 1;
    return a.name.localeCompare(b.name);
}));

const loadData = async () => {
    try {
        const repoResp = await apiClient.get(versionManagementEndpoints.repositories.retrieve(repoId));
        if (repoResp.success) repo.value = repoResp.data;

        const branchResp = await apiClient.get(versionManagementEndpoints.repositories.branches(repoId));
         if (branchResp.success && branchResp.data) {
            branches.value = branchResp.data.map(b => ({ name: b.name || b }));
            if (branches.value.length > 0) {
                 // Try to keep current branch or default to first/main
                 if (!currentBranch.value || !branches.value.find(b => b.name === currentBranch.value)) {
                     currentBranch.value = branches.value[0].name;
                 }
            } else {
                 currentBranch.value = 'main'; // Fallback
            }
            console.log('RepoFiles: configured branch', currentBranch.value);
            await loadBranchFiles();
        } else {
             console.warn('RepoFiles: No branches found');
        }
    } catch (e) { console.error(e); } 
    finally { loading.value = false; }
};

const loadBranchFiles = async () => {
    loadingFiles.value = true;
    selectedFile.value = null; // Reset selection on nav
    try {
        const response = await apiClient.get(
            versionManagementEndpoints.repositories.branchFiles(repoId, currentBranch.value) + `?path=${currentPath.value}`
        );
        if (response.success && response.data) {
            files.value = response.data.filter(f => f.name !== 'commit.json');
        }
    } catch (e) {
        files.value = [];
        console.error(e);
    } finally { loadingFiles.value = false; }
};

const navigateDir = (part, index) => {
    if (part === '') currentPath.value = '';
    else {
        const parts = currentPath.value.split('/').filter(Boolean);
        currentPath.value = parts.slice(0, index + 1).join('/');
    }
    loadBranchFiles();
};

const goUp = () => {
    const parts = currentPath.value.split('/').filter(Boolean);
    parts.pop();
    currentPath.value = parts.join('/');
    loadBranchFiles();
};

const handleFileClick = async (file) => {
    if (file.type === 'dir') {
        currentPath.value = file.path;
        loadBranchFiles();
    } else {
        selectedFile.value = file;
        await loadFileContent(file.path);
    }
};

const loadFileContent = async (path) => {
    try {
        const response = await apiClient.get(
             versionManagementEndpoints.repositories.fileContent(repoId, currentBranch.value) + `?path=${path}`
        );
        if (response.success) {
            fileContent.value = response.data.content;
        }
    } catch (e) { toast.error('Ошибка загрузки файла'); }
};

const saveFile = async () => {
    if (!selectedFile.value) return;
    try {
        const response = await apiClient.post(
            versionManagementEndpoints.repositories.fileUpdate(repoId, currentBranch.value),
            { path: selectedFile.value.path, content: fileContent.value }
        );
        if (response.success) toast.success('Файл сохранен');
        else toast.error(response.message || 'Ошибка');
    } catch (e) { toast.error('Ошибка сети'); }
};

const handleDrop = (event) => {
    dragActive.value = false;
    const droppedFiles = event.dataTransfer.files;
    if (droppedFiles.length > 0) uploadFiles(droppedFiles);
};

const uploadFiles = async (fileList) => {
    const uploadPromises = Array.from(fileList).map(async (file) => {
        const formData = new FormData();
        formData.append('file', file);
        formData.append('path', currentPath.value);

        try {
            const response = await apiClient.post(versionManagementEndpoints.repositories.uploadFile(repo.value.public_id, currentBranch.value), formData);
            if (response.success) {
                toast.success(`Файл ${file.name} загружен`);
                return true;
            } else {
                toast.error(`Ошибка загрузки ${file.name}: ${response.message || 'Error'}`);
                return false;
            }
        } catch (e) {
            console.error(e);
            toast.error(`Ошибка сети при загрузке ${file.name}`);
            return false;
        }
    });

    await Promise.all(uploadPromises);
    await loadBranchFiles();
};

onMounted(() => loadData());
</script>

<style scoped>
.repository-files-page { 
    height: calc(100vh - 100px); 
    display: flex; 
    flex-direction: column; 
    padding: 20px; 
}

.ide-container { 
    background: var(--color-primary-background); 
    border: 1px solid var(--color-border); 
    border-radius: 6px; 
    overflow: hidden; 
}

.sidebar { 
    background: var(--color-secondary-background); 
}

.sidebar-header {
    background: var(--color-primary-background);
    border-color: var(--color-border) !important;
}

.main-content {
    background: var(--color-primary-background);
}

.editor-header {
    background: var(--color-secondary-background);
    border-color: var(--color-border) !important;
}

.editor-textarea {
    background: var(--color-primary-background);
    color: var(--color-primary-text);
}

.cursor-pointer { cursor: pointer; }

.file-item:hover { 
    background: var(--color-hover-background); 
}

.file-item.active { 
    background: var(--color-hover-background); 
}

.hover-text-white:hover { 
    color: var(--color-primary-text); 
    text-decoration: underline; 
}

.border-primary { 
    border-color: var(--color-accent) !important; 
}
</style>
