<template>
  <div class="commit-create-page">
    <div class="header mb-4">
      <router-link :to="{ name: 'RepositoryDetail', params: { id: repoId } }" class="btn btn-outline-secondary mb-3">
        &larr; Назад к репозиторию
      </router-link>
      <h1>Создать коммит</h1>
    </div>

    <div class="card">
        <div class="card-body">
            <form @submit.prevent="createCommit">
                <div class="mb-3">
                    <label for="message" class="form-label">Сообщение коммита</label>
                    <textarea 
                        id="message" 
                        v-model="form.message" 
                        class="form-control" 
                        rows="3" 
                        required
                        placeholder="Введите описание изменений..."
                    ></textarea>
                </div>
                
                <div class="alert alert-info">
                    <small>
                        <i class="bi bi-info-circle"></i> 
                        Примечание: Перед созданием коммита убедитесь, что файлы добавлены в индекс (staged).
                        Этот интерфейс создает коммит из текущих изменений в рабочей директории репозитория.
                    </small>
                </div>

                <div class="d-flex justify-content-end">
                    <button type="submit" class="btn btn-success" :disabled="loading">
                        <span v-if="loading" class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>
                        Создать коммит
                    </button>
                </div>
            </form>
        </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';
import { useToast } from 'vue-toastification';

const route = useRoute();
const router = useRouter();
const toast = useToast();

const repoId = route.params.id;
const loading = ref(false);

const form = reactive({
    message: ''
});

const createCommit = async () => {
    if (!form.message.trim()) return;

    loading.value = true;
    try {
        const response = await apiClient.post(versionManagementEndpoints.version_management.commit_create(repoId), {
            message: form.message
        });

        if (response.success) {
            toast.success('Коммит успешно создан');
            router.push({ name: 'RepositoryDetail', params: { id: repoId } });
        } else {
            toast.error(response.message || 'Ошибка создания коммита');
        }
    } catch (error) {
        toast.error('Ошибка сети или сервера');
        console.error(error);
    } finally {
        loading.value = false;
    }
};
</script>

<style scoped>
.commit-create-page {
    padding: 20px;
}
</style>
