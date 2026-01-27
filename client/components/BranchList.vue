<template>
  <div class="branch-list-page" v-if="repo">
    <div class="header d-flex justify-content-between align-items-center mb-4">
      <div class="d-flex align-items-center">
        <router-link :to="{ name: 'RepositoryDetail', params: { id: repoId } }" class="btn btn-outline-secondary back-btn me-3 d-flex align-items-center">
            <ArrowLeft :size="16" class="me-2" /> Назад к репозиторию
        </router-link>
        <h1>Ветки репозитория {{ repo.name }}</h1>
      </div>
    </div>

    <div class="card bg-dark border-secondary">
        <div class="card-header border-secondary d-flex justify-content-between align-items-center">
            <h5 class="m-0">Все ветки ({{ branches.length }})</h5>
            <!-- Future: Search/Filter -->
        </div>
        <div class="card-body p-0">
            <div class="table-responsive">
                <table class="table table-dark table-hover mb-0">
                    <thead>
                        <tr>
                            <th>Имя ветки</th>
                            <th>Дата создания</th>
                            <th>Действия</th>
                        </tr>
                    </thead>
                    <tbody>
                        <tr v-for="branch in branches" :key="branch.id">
                            <td>
                                <div class="d-flex align-items-center gap-2">
                                    <GitBranch :size="16" :class="{'text-warning': branch.is_default}" />
                                    <span :class="{'fw-bold text-warning': branch.is_default}">{{ branch.name }}</span>
                                    <span v-if="branch.is_default" class="badge bg-warning text-dark small">Default</span>
                                </div>
                            </td>
                            <td>{{ formatDate(branch.created_at) }}</td>
                            <td>
                                <button v-if="!branch.is_default" class="btn btn-sm btn-outline-danger d-flex align-items-center gap-1" @click="deleteBranch(branch)">
                                    <Trash2 :size="14" /> Удалить
                                </button>
                                <span v-else class="text-muted small">Нельзя удалить</span>
                            </td>
                        </tr>
                        <tr v-if="branches.length === 0">
                            <td colspan="3" class="text-center p-4 text-muted">Ветки не найдены</td>
                        </tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
  </div>
  <div v-else-if="loading" class="p-4 text-center">Загрузка...</div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints.js';
import { useToast } from 'vue-toastification';
import { ArrowLeft, GitBranch, Trash2 } from 'lucide-vue-next';

const route = useRoute();
const toast = useToast();
const repoId = route.params.id;
const repo = ref(null);
const branches = ref([]);
const loading = ref(true);

const loadData = async () => {
    loading.value = true;
    try {
        // Load Repo Info
        const repoResp = await apiClient.get(versionManagementEndpoints.repositories.retrieve(repoId));
        if (repoResp.success) {
            repo.value = repoResp.data;
        }

        // Load Branches
        const branchResp = await apiClient.get(versionManagementEndpoints.repositories.branches(repoId));
        if (branchResp.success) {
            branches.value = branchResp.data;
        }
    } catch (e) {
        toast.error('Ошибка загрузки данных');
        console.error(e);
    } finally {
        loading.value = false;
    }
};

const deleteBranch = async (branch) => {
    if (!confirm(`Вы уверены, что хотите удалить ветку "${branch.name}"? Это действие необратимо.`)) return;

    try {
        const response = await apiClient.delete(versionManagementEndpoints.branches.delete(branch.id));
        if (response.success) {
            toast.success(`Ветка ${branch.name} удалена`);
            await loadData(); // Reload list
        } else {
            toast.error(response.message || 'Ошибка удаления');
        }
    } catch (e) {
        toast.error('Ошибка сети при удалении');
        console.error(e);
    }
};

const formatDate = (dateStr) => {
    return new Date(dateStr).toLocaleString();
};

onMounted(() => {
    loadData();
});
</script>

<style scoped>
.branch-list-page { padding: 20px; max-width: 1000px; margin: 0 auto; }
.back-btn { font-weight: 600; transition: all 0.2s; }
.back-btn:hover { background-color: #dc2626 !important; color: #ffffff !important; border-color: #dc2626 !important; }
.card { background-color: var(--bs-card-bg); }
.table-dark { --bs-table-bg: transparent; }
</style>
