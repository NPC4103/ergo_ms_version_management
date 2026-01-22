<template>
  <div class="repository-detail-page" v-if="repo">
    <div class="header d-flex justify-content-between align-items-center mb-4">
      <div class="d-flex align-items-center">
         <router-link :to="{ name: 'RepositoryList' }" class="btn btn-outline-secondary me-3">
            &larr; Назад
         </router-link>
         <h1>{{ repo.name }}</h1>
      </div>
      <div class="actions d-flex gap-2">
         <button class="btn btn-success" @click="pushRepo" :disabled="loadingAction">Push</button>
         <button class="btn btn-info text-white" @click="updateRepo" :disabled="loadingAction">Update (Pull)</button>
         <button class="btn btn-secondary" @click="cloneRepo" :disabled="loadingAction">Clone</button>
         <button class="btn btn-danger" @click="deleteRepo" :disabled="loadingAction">Delete</button>
      </div>
    </div>
    
    <div class="card mb-4">
        <div class="card-body">
            <p class="text-muted">{{ repo.description }}</p>
            <p><small>ID: {{ repo.id }}</small></p>
            <p><small>Created: {{ repo.created_at }}</small></p>
        </div>
    </div>

    <!-- Commit Management Section -->
    <div class="commits-section">
        <div class="d-flex justify-content-between align-items-center mb-3">
            <h3>История коммитов</h3>
            <router-link :to="{ name: 'CommitCreate', params: { id: repo.id } }" class="btn btn-primary btn-sm">
                Создать коммит
            </router-link>
        </div>
         <!-- Could be a separate component, but putting list here for simplicity as per requirements list -> detail -> commits -->
         <CommitList :repoId="repo.id" />
    </div>

  </div>
  <div v-else-if="loading" class="p-4 text-center">
    Загрузка...
  </div>
  <div v-else class="p-4 text-center text-danger">
    Репозиторий не найден
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';
import { useToast } from 'vue-toastification';
import CommitList from './CommitList.vue';

const route = useRoute();
const router = useRouter();
const toast = useToast();

const repoId = route.params.id;
const repo = ref(null);
const loading = ref(true);
const loadingAction = ref(false);

const loadRepo = async () => {
    loading.value = true;
    try {
        const response = await apiClient.get(versionManagementEndpoints.version_management.retrieve(repoId));
        if (response.success) {
            repo.value = response.data;
        } else {
            toast.error(response.message || 'Ошибка загрузки репозитория');
        }
    } catch (error) {
        toast.error('Ошибка сети');
        console.error(error);
    } finally {
        loading.value = false;
    }
};

const updateRepo = async () => {
    loadingAction.value = true;
    try {
        const response = await apiClient.post(versionManagementEndpoints.version_management.update(repoId));
        if (response.success) {
            toast.success('Репозиторий обновлен');
            // Refresh commits maybe?
        } else {
            toast.error(response.message || 'Ошибка обновления');
        }
    } catch (error) {
        toast.error('Ошибка выполнения операции');
    } finally {
        loadingAction.value = false;
    }
};

const cloneRepo = async () => {
    loadingAction.value = true;
    try {
        const response = await apiClient.post(versionManagementEndpoints.version_management.clone(repoId));
         if (response.success) {
            toast.success('Репозиторий клонирован');
        } else {
            toast.error(response.message || 'Ошибка клонирования');
        }
    } catch (error) {
        toast.error('Ошибка выполнения операции');
    } finally {
        loadingAction.value = false;
    }
};

const pushRepo = async () => {
    loadingAction.value = true;
    try {
        const response = await apiClient.post(versionManagementEndpoints.version_management.push(repoId));
         if (response.success) {
            toast.success('Изменения отправлены');
        } else {
            toast.error(response.message || 'Ошибка отправки (Push)');
        }
    } catch (error) {
        toast.error('Ошибка выполнения операции');
    } finally {
        loadingAction.value = false;
    }
};

const deleteRepo = async () => {
    if(!confirm('Вы уверены? Это действие необратимо.')) return;
    loadingAction.value = true;
    try {
        const response = await apiClient.delete(versionManagementEndpoints.version_management.delete(repoId));
        if (response.success) {
            toast.success('Репозиторий удален');
            router.push({ name: 'RepositoryList' });
        } else {
            toast.error(response.message || 'Ошибка удалени');
        }
    } catch (error) {
         toast.error('Ошибка выполнения операции');
    } finally {
        loadingAction.value = false;
    }
};

onMounted(() => {
    loadRepo();
});
</script>

<style scoped>
.repository-detail-page {
    padding: 20px;
}
</style>
