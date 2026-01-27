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

      <!-- Владельцы / участники -->
      <div class="settings-card mb-4">
        <h5>Владельцы репозитория</h5>
        <p class="text-muted small mb-3">
          Добавьте пользователей, которые будут иметь права владельцев (администраторов) для этого репозитория.
        </p>

        <div class="mb-3">
          <label class="form-label fw-bold">Выбрать владельцев</label>
          <div class="dropdown">
            <button
              class="btn btn-outline-secondary w-100 text-start d-flex justify-content-between align-items-center"
              type="button"
              data-bs-toggle="dropdown"
              aria-expanded="false"
            >
              <span>Выберите пользователей...</span>
              <i class="bi bi-chevron-down"></i>
            </button>
            <div class="dropdown-menu w-100 p-2 owners-dropdown">
              <input
                type="text"
                class="form-control mb-2"
                placeholder="Поиск пользователей..."
                v-model="ownerSearch"
              >
              <div
                v-if="filteredOwnerUsers.length === 0"
                class="text-muted text-center py-2 text-small"
              >
                Никого не найдено
              </div>
              <div
                v-for="user in filteredOwnerUsers"
                :key="user.user_id"
                class="form-check dropdown-item p-2 rounded"
              >
                <input
                  class="form-check-input ms-0 me-2"
                  type="checkbox"
                  :value="user.user_id"
                  :id="'owner-user-' + user.user_id"
                  v-model="selectedOwners"
                >
                <label
                  class="form-check-label w-100 cursor-pointer"
                  :for="'owner-user-' + user.user_id"
                >
                  {{ user.full_name || user.username }}
                  <span class="text-muted small">({{ user.username }})</span>
                </label>
              </div>
            </div>
          </div>
          <div
            class="mt-2 d-flex flex-wrap gap-2"
            v-if="selectedOwnerUsers.length > 0"
          >
            <span
              v-for="user in selectedOwnerUsers"
              :key="user.user_id"
              class="badge bg-light text-dark border d-flex align-items-center owner-badge"
            >
              {{ user.full_name || user.username }}
              <button
                type="button"
                class="btn-close ms-2 owner-remove-btn"
                @click="removeSelectedOwner(user.user_id)"
              ></button>
            </span>
          </div>
        </div>

        <div class="mb-3">
          <button
            class="btn btn-success"
            @click="saveOwners"
            :disabled="ownersSaving || selectedOwners.length === 0"
          >
            <span
              v-if="ownersSaving"
              class="spinner-border spinner-border-sm me-2"
              role="status"
              aria-hidden="true"
            ></span>
            Сохранить владельцев
          </button>
        </div>

        <div>
          <h6 class="mt-3 mb-2">Текущие владельцы и участники</h6>
          <div v-if="ownersLoading" class="text-muted small">Загрузка списка...</div>
          <div v-else-if="collaborators.length === 0" class="text-muted small">
            Для репозитория еще не добавлены владельцы или участники.
          </div>
          <ul v-else class="list-unstyled mb-0">
            <li
              v-for="collab in collaborators"
              :key="collab.id"
              class="d-flex align-items-center justify-content-between py-1"
            >
              <div>
                <span class="fw-semibold">{{ collab.user_display_name }}</span>
                <span class="badge ms-2" :class="collab.role === 'admin' ? 'bg-danger' : 'bg-secondary'">
                  {{ collab.role === 'admin' ? 'Владелец (админ)' : (collab.role === 'write' ? 'Запись' : 'Чтение') }}
                </span>
              </div>
              <button
                v-if="collab.role === 'admin'"
                class="btn btn-sm btn-outline-danger"
                @click="removeOwner(collab)"
                :disabled="ownersSaving"
              >
                Удалить
              </button>
            </li>
          </ul>
        </div>
      </div>

      <!-- Опасная зона -->
      <div class="settings-card danger-zone">
        <h5 class="text-danger">Опасная зона</h5>
        <p class="text-muted">Удаление репозитория необратимо. Все данные будут потеряны.</p>
        <button class="btn btn-danger" @click="showDeleteDialog = true" :disabled="deleting">
          <span v-if="deleting" class="spinner-border spinner-border-sm me-1"></span>
          Удалить репозиторий
        </button>
      </div>
    </div>

    <ConfirmDialog
      :show="showDeleteDialog"
      title="Удалить репозиторий?"
      :message="`Вы уверены, что хотите удалить репозиторий «${form.name || repo?.name}»? Это действие необратимо.`"
      confirmText="Удалить"
      variant="danger"
      @confirm="confirmDeleteRepo"
      @close="showDeleteDialog = false"
      @cancel="showDeleteDialog = false"
    />
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints.js';
import { useToast } from 'vue-toastification';
import ConfirmDialog from '@/components/ConfirmDialog.vue';
import { GetAdminUsers } from '@/core/cms/adp/admin/js/GroupsPolitics';

const route = useRoute();
const router = useRouter();
const toast = useToast();

const repoId = route.params.id;
const repo = ref(null);
const loading = ref(true);
const saving = ref(false);
const deleting = ref(false);
const showDeleteDialog = ref(false);

const collaborators = ref([]);
const ownersLoading = ref(false);
const ownersSaving = ref(false);
const allUsers = ref([]);
const ownerSearch = ref('');
const selectedOwners = ref([]);

const form = reactive({
  name: '',
  description: ''
});

const filteredOwnerUsers = computed(() => {
  if (!ownerSearch.value) return allUsers.value;
  const query = ownerSearch.value.toLowerCase();
  return allUsers.value.filter(u =>
    (u.username && u.username.toLowerCase().includes(query)) ||
    (u.full_name && u.full_name.toLowerCase().includes(query))
  );
});

const selectedOwnerUsers = computed(() =>
  allUsers.value.filter(u => selectedOwners.value.includes(u.user_id))
);

const loadRepository = async () => {
  const response = await apiClient.get(versionManagementEndpoints.repositories.retrieve(repoId));
  if (response.success) {
    repo.value = response.data;
    form.name = response.data.name || '';
    form.description = response.data.description || '';
  }
};

const loadCollaborators = async () => {
  ownersLoading.value = true;
  try {
    const response = await apiClient.get(versionManagementEndpoints.collaborators.byRepository, {
      params: { repository_public_id: repoId }
    });
    if (response.data) {
      collaborators.value = response.data.collaborators || [];
      // Предзаполняем выбранных владельцев по роли admin
      const adminIds = collaborators.value
        .filter(c => c.role === 'admin')
        .map(c => c.user_id);
      if (adminIds.length) {
        selectedOwners.value = adminIds;
      }
    }
  } catch (e) {
    // Не критично для работы страницы, просто логируем
    console.error('Не удалось загрузить коллабораторов репозитория', e?.response || e);
  } finally {
    ownersLoading.value = false;
  }
};

const loadUsers = async () => {
  try {
    const users = await GetAdminUsers();
    allUsers.value = users || [];
  } catch (e) {
    // Ошибка не критична для основной информации
    console.error('Failed to load users for owners', e);
  }
};

onMounted(async () => {
  loading.value = true;
  try {
    // Загружаем данные репозитория, список пользователей и коллабораторов
    await Promise.all([
      loadRepository(),
      loadUsers(),
      loadCollaborators()
    ]);

    // Если коллабораторы ещё не загружены или владельца нет в списке — добавляем владельца из репозитория
    if (repo.value && allUsers.value.length) {
      const ownerUser = allUsers.value.find(u => u.user_id === repo.value.owner_id);
      const hasOwnerInCollaborators = collaborators.value.some(
        c => c.user_id === repo.value.owner_id
      );
      if (ownerUser && !hasOwnerInCollaborators) {
        const displayName = ownerUser.full_name || ownerUser.username || `User #${ownerUser.user_id}`;
        collaborators.value.push({
          id: ownerUser.user_id,
          user_id: ownerUser.user_id,
          user_display_name: displayName,
          role: 'admin'
        });
      }
      // Гарантируем, что владелец есть среди выбранных владельцев
      if (ownerUser && !selectedOwners.value.includes(ownerUser.user_id)) {
        selectedOwners.value.push(ownerUser.user_id);
      }
    }
  } catch (e) {
    toast.error('Ошибка загрузки настроек репозитория');
  } finally {
    loading.value = false;
  }
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

const deleteRepo = async () => {
  deleting.value = true;
  try {
    await apiClient.delete(versionManagementEndpoints.repositories.delete(repoId));
    toast.success('Репозиторий удален');
    router.push({ name: 'RepositoryList' });
  } catch { toast.error('Ошибка удаления'); }
  finally { deleting.value = false; }
};

const confirmDeleteRepo = async () => {
  showDeleteDialog.value = false;
  await deleteRepo();
};

const removeSelectedOwner = (userId) => {
  selectedOwners.value = selectedOwners.value.filter(id => id !== userId);
};

const saveOwners = async () => {
  if (selectedOwners.value.length === 0) {
    return;
  }

  ownersSaving.value = true;
  try {
    // Определяем уже существующих коллабораторов и админов
    const existingCollaboratorIds = collaborators.value.map(c => c.user_id);
    const existingAdminIds = collaborators.value
      .filter(c => c.role === 'admin')
      .map(c => c.user_id);

    // Пользователи, которых нужно добавить как новых владельцев
    const toAdd = selectedOwners.value.filter(
      userId => !existingCollaboratorIds.includes(userId)
    );

    // Пользователи, которые уже есть среди коллабораторов
    const alreadyCollaborators = selectedOwners.value.filter(userId =>
      existingCollaboratorIds.includes(userId)
    );

    // Если все выбранные уже являются коллабораторами — просто показываем информацию и выходим
    if (toAdd.length === 0 && alreadyCollaborators.length > 0) {
      toast.info('Выбранные пользователи уже являются участниками этого репозитория');
      return;
    }

    for (const userId of toAdd) {
      await apiClient.post(
        versionManagementEndpoints.repositories.collaborators(repoId),
        {
          repository_public_id: repoId,
          user_id: userId,
          role: 'admin'
        }
      );
    }

    toast.success('Список владельцев обновлен');

    // Обновляем локальный список владельцев на основе выбранных пользователей
    toAdd.forEach((userId) => {
      const user = allUsers.value.find(u => u.user_id === userId);
      const displayName = user?.full_name || user?.username || `User #${userId}`;
      collaborators.value.push({
        id: userId,
        user_id: userId,
        user_display_name: displayName,
        role: 'admin'
      });
    });
  } catch (e) {
    // Показываем детальное сообщение от бэкенда, чтобы понять причину
    const backendMessage =
      e?.response?.data?.error ||
      e?.response?.data?.detail ||
      (typeof e?.response?.data === 'object'
        ? Object.values(e.response.data).flat().join(', ')
        : null);

    console.error('Ошибка сохранения владельцев:', e?.response || e);

    // Если бэкенд сообщает, что пользователь уже является коллаборатором,
    // не считаем это ошибкой: обновляем список коллабораторов и показываем информативный тост
    if (
      backendMessage &&
      backendMessage.includes('Пользователь уже является коллаборатором этого репозитория')
    ) {
      toast.info('Выбранный пользователь уже является участником этого репозитория');
      await loadCollaborators();
    } else {
      toast.error(backendMessage || 'Ошибка сохранения владельцев');
    }
  } finally {
    ownersSaving.value = false;
  }
};

const removeOwner = async (collab) => {
  ownersSaving.value = true;
  try {
    await apiClient.delete(versionManagementEndpoints.collaborators.delete(collab.id));
    toast.success('Владелец удален');

    // Обновляем локальное состояние после удаления
    collaborators.value = collaborators.value.filter(c => c.id !== collab.id);
    selectedOwners.value = selectedOwners.value.filter(id => id !== collab.user_id);
  } catch (e) {
    toast.error('Ошибка удаления владельца');
  } finally {
    ownersSaving.value = false;
  }
};
</script>

<style scoped>
.repository-settings-page { padding: 20px; max-width: 800px; margin: 0 auto; }
.settings-card { background: rgba(0,0,0,0.3); border-radius: 8px; padding: 20px; }
.settings-card h5 { margin-bottom: 15px; }
.danger-zone { border: 1px solid #dc2626; }
.owners-dropdown {
  max-height: 300px;
  overflow-y: auto;
  background-color: #111111; /* плотный чёрный фон */
  border-radius: 0.375rem;
  border: 1px solid #4b5563; /* лёгкая окантовка, чтобы не сливалось */
  box-shadow: 0 10px 25px rgba(0, 0, 0, 0.6);
}
.owners-dropdown .dropdown-item {
  background-color: #111111;
  color: #f9fafb;
}
.owners-dropdown .dropdown-item:hover {
  background-color: #1f2937;
  color: #f9fafb;
}
.cursor-pointer { cursor: pointer; }
.owner-badge { font-size: 0.9rem; }
.owner-remove-btn { font-size: 0.5rem; }
</style>
