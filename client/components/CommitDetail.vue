<template>
  <div class="commit-detail-page">
     <div class="d-flex align-items-center mb-4">
      <router-link :to="{ name: 'RepositoryDetail', params: { id: repoId } }" class="btn btn-outline-secondary me-3">
        &larr; Назад к репозиторию
      </router-link>
      <h1>Коммит <small class="text-muted">{{ commitHash }}</small></h1>
    </div>

    <div v-if="commit" class="card mb-4">
        <div class="card-header">
            Метаданные
        </div>
        <div class="card-body">
            <p><strong>Message:</strong> {{ commit.message }}</p>
            <p><strong>Author:</strong> {{ commit.author }}</p>
            <p><strong>Date:</strong> {{ formatDate(commit.date) }}</p>
        </div>
    </div>

    <div class="card">
        <div class="card-header">
            Изменения
        </div>
        <div class="card-body">
            <div v-if="loadingDiff" class="text-center">Загрузка изменений...</div>
            <div v-else-if="diff">
                <pre class="diff-content">{{ diff }}</pre>
            </div>
            <div v-else class="text-muted">Нет изменений или не удалось загрузить.</div>
        </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';
import { useToast } from 'vue-toastification';

const route = useRoute();
const toast = useToast();

const repoId = route.params.id;
const commitHash = route.params.hash;

const commit = ref(null);
const diff = ref('');
const loading = ref(false);
const loadingDiff = ref(false);

const formatDate = (dateString) => {
    if (!dateString) return '';
    return new Date(dateString).toLocaleString();
};

const loadCommit = async () => {
    loading.value = true;
    try {
        const response = await apiClient.get(versionManagementEndpoints.version_management.commit_retrieve(repoId, commitHash));
        if (response.success) {
            commit.value = response.data;
        } else {
            toast.error('Не удалось загрузить информацию о коммите');
        }
    } catch (error) {
        console.error(error);
    } finally {
        loading.value = false;
    }
};

const loadDiff = async () => {
    loadingDiff.value = true;
    try {
        // According to specs, returns raw diff string
        const response = await apiClient.get(versionManagementEndpoints.version_management.commit_diff(repoId, commitHash));
        if (response.success) {
            diff.value = response.data; // Assuming data contains the string directly or field
        } 
    } catch (error) {
        console.error("Failed to load diff", error);
    } finally {
        loadingDiff.value = false;
    }
};

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
}
.diff-content {
    background: #f6f8fa;
    padding: 15px;
    border-radius: 4px;
    overflow-x: auto;
    font-family: 'Courier New', Courier, monospace;
    white-space: pre-wrap;
}
</style>
