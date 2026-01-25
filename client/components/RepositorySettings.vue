<template>
  <div class="repository-settings-page">
    <div class="header d-flex align-items-center mb-4">
      <router-link :to="{ name: 'RepositoryDetail', params: { id: repoId } }" class="btn btn-outline-secondary me-3">&larr; Назад</router-link>
      <h1>Настройки репозитория</h1>
    </div>

    <div v-if="loading" class="text-center py-5">
      <div class="spinner-border text-danger"></div>
    </div>

    <div v-else-if="repo" class="settings-content">
      <!-- Основные настройки -->
      <div class="settings-card mb-4">
        <h5>Основная информация</h5>
        <div class="mb-3">
          <label class="form-label">Название</label>
          <input type="text" class="form-control" v-model="form.name">
        </div>
        <div class="mb-3">
          <label class="form-label">Описание</label>
          <textarea class="form-control" rows="3" v-model="form.description"></textarea>
        </div>
        <button class="btn btn-primary" @click="saveSettings" :disabled="saving">
          <span v-if="saving" class="spinner-border spinner-border-sm me-1"></span>
          Сохранить
        </button>
      </div>

      <!-- Теги -->
      <div class="settings-card mb-4">
        <h5>Теги</h5>
        <div class="tags-list mb-3">
          <span v-for="tag in tags" :key="tag" class="tag-badge">
            {{ tag }}
            <button class="tag-remove" @click="removeTag(tag)">&times;</button>
          </span>
          <span v-if="tags.length === 0" class="text-muted">Нет тегов</span>
        </div>
        <div class="input-group" style="max-width: 300px;">
          <input type="text" class="form-control" v-model="newTag" placeholder="Новый тег">
          <button class="btn btn-outline-success" @click="addTag">Добавить</button>
        </div>
      </div>

      <!-- Опасная зона -->
      <div class="settings-card danger-zone">
        <h5 class="text-danger">Опасная зона</h5>
        <p class="text-muted">Удаление репозитория необратимо. Все данные будут потеряны.</p>
        <button class="btn btn-danger" @click="deleteRepo" :disabled="deleting">
          <span v-if="deleting" class="spinner-border spinner-border-sm me-1"></span>
          🗑️ Удалить репозиторий
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints.js';
import { useToast } from 'vue-toastification';

const route = useRoute();
const router = useRouter();
const toast = useToast();

const repoId = route.params.id;
const repo = ref(null);
const loading = ref(true);
const saving = ref(false);
const deleting = ref(false);
const tags = ref([]);
const newTag = ref('');

const form = reactive({
  name: '',
  description: ''
});

onMounted(async () => {
  loading.value = true;
  try {
    const response = await apiClient.get(versionManagementEndpoints.repositories.retrieve(repoId));
    if (response.success) {
      repo.value = response.data;
      form.name = response.data.name || '';
      form.description = response.data.description || '';
      tags.value = response.data.tags || [];
    }
  } catch (e) { toast.error('Ошибка загрузки'); }
  finally { loading.value = false; }
});

const saveSettings = async () => {
  saving.value = true;
  try {
    await apiClient.patch(versionManagementEndpoints.repositories.update(repoId), {
      name: form.name,
      description: form.description
    });
    toast.success('Настройки сохранены');
  } catch { toast.error('Ошибка сохранения'); }
  finally { saving.value = false; }
};

const addTag = () => {
  if (newTag.value.trim() && !tags.value.includes(newTag.value.trim())) {
    tags.value.push(newTag.value.trim());
    newTag.value = '';
    toast.success('Тег добавлен');
  }
};

const removeTag = (tag) => {
  tags.value = tags.value.filter(t => t !== tag);
  toast.info('Тег удален');
};

const deleteRepo = async () => {
  if (!confirm('Удалить репозиторий? Это необратимо!')) return;
  deleting.value = true;
  try {
    await apiClient.delete(versionManagementEndpoints.repositories.delete(repoId));
    toast.success('Репозиторий удален');
    router.push({ name: 'RepositoryList' });
  } catch { toast.error('Ошибка удаления'); }
  finally { deleting.value = false; }
};
</script>

<style scoped>
.repository-settings-page { padding: 20px; max-width: 800px; margin: 0 auto; }
.settings-card { background: rgba(0,0,0,0.3); border-radius: 8px; padding: 20px; }
.settings-card h5 { margin-bottom: 15px; }
.danger-zone { border: 1px solid #dc2626; }
.tags-list { display: flex; flex-wrap: wrap; gap: 8px; }
.tag-badge { background: #3b82f6; color: white; padding: 4px 10px; border-radius: 20px; display: inline-flex; align-items: center; gap: 6px; font-size: 14px; }
.tag-remove { background: none; border: none; color: white; font-size: 16px; cursor: pointer; padding: 0; line-height: 1; }
.tag-remove:hover { color: #fca5a5; }
</style>
