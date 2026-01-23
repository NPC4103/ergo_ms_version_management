<template>
  <div class="commit-list">
    <div v-if="commits.length > 0" class="list-group">
        <router-link 
            v-for="commit in commits" 
            :key="commit.hash" 
            :to="{ name: 'CommitDetail', params: { id: repoId, hash: commit.hash } }"
            class="list-group-item list-group-item-action"
        >
            <div class="d-flex w-100 justify-content-between">
            <h5 class="mb-1">{{ commit.message || 'Без сообщения' }}</h5>
            <small>{{ formatDate(commit.date) }}</small>
            </div>
            <p class="mb-1">Author: {{ commit.author }}</p>
            <small class="text-muted">Hash: {{ commit.hash }}</small>
        </router-link>
    </div>
    <div v-else-if="!loading" class="alert alert-light">
        Нет коммитов.
    </div>
    <div v-if="loading" class="text-center mt-2">
        <span class="spinner-border spinner-border-sm" role="status" aria-hidden="true"></span>
        Загрузка истории...
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, watch } from 'vue';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';

const props = defineProps({
    repoId: {
        type: [String, Number],
        required: true
    }
});

const commits = ref([]);
const loading = ref(false);

const loadCommits = async () => {
    loading.value = true;
    try {
        const response = await apiClient.get(versionManagementEndpoints.version_management.commits_list(props.repoId));
        if (response.success) {
            // Assuming flat list for now, backend might return tree
            commits.value = Array.isArray(response.data) ? response.data : (response.data.results || []);
        }
    } catch (error) {
        console.error("Failed to load commits", error);
    } finally {
        loading.value = false;
    }
};

const formatDate = (dateString) => {
    if (!dateString) return '';
    return new Date(dateString).toLocaleString();
};

onMounted(() => {
    loadCommits();
});

watch(() => props.repoId, () => {
    loadCommits();
});
</script>

<style scoped>
.commit-list {
    margin-top: 1rem;
}
</style>
