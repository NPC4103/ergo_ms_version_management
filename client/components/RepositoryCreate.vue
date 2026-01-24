<template>
  <div class="repository-create-page">
    <div class="container-fluid">
        <div class="row justify-content-center">
            <div class="col-12 col-md-8 col-lg-6">
                <div class="card shadow-sm mt-4">
                    <div class="card-header bg-danger text-white py-3">
                        <h4 class="mb-0">Создание нового репозитория</h4>
                    </div>
                    <div class="card-body p-4">
                        <form @submit.prevent="createRepo">
                            <div class="mb-3">
                                <label for="name" class="form-label">Название репозитория <span class="text-danger">*</span></label>
                                <input type="text" class="form-control" id="name" v-model="form.name" required placeholder="Например: my-awesome-project">
                                <div class="form-text">Краткое и уникальное имя для вашего проекта.</div>
                            </div>

                            <div class="mb-3">
                                <label for="description" class="form-label">Описание</label>
                                <textarea class="form-control" id="description" v-model="form.description" rows="3" placeholder="О чем этот проект?"></textarea>
                            </div>

                             <hr class="my-4">

                            <!-- Visibility -->
                            <div class="mb-4">
                                <label class="form-label d-block fw-bold">Видимость</label>
                                <div class="form-check">
                                    <input class="form-check-input" type="radio" name="visibility" id="visibilityPublic" value="public" v-model="form.visibility">
                                    <label class="form-check-label" for="visibilityPublic">
                                        <i class="bi bi-globe me-1"></i> Public
                                        <div class="text-muted small">Каждый может видеть этот репозиторий. Выбирайте, кто может совершать коммиты.</div>
                                    </label>
                                </div>
                                <div class="form-check mt-2">
                                    <input class="form-check-input" type="radio" name="visibility" id="visibilityPrivate" value="private" v-model="form.visibility">
                                    <label class="form-check-label" for="visibilityPrivate">
                                        <i class="bi bi-lock me-1"></i> Private
                                        <div class="text-muted small">Вы сами выбираете, кто может видеть и совершать коммиты в этот репозиторий.</div>
                                    </label>
                                </div>
                            </div>

                            <!-- License -->
                            <div class="mb-3">
                                <label for="license" class="form-label fw-bold">Лицензия</label>
                                <select class="form-select" id="license" v-model="form.license">
                                    <option value="none">Без лицензии</option>
                                    <option value="mit">MIT License</option>
                                    <option value="apache-2.0">Apache License 2.0</option>
                                    <option value="gpl-3.0">GNU General Public License v3.0</option>
                                    <option value="bsd-3-clause">BSD 3-Clause "New" or "Revised" License</option>
                                </select>
                                <div class="form-text">Лицензия сообщает другим, что они могут и не могут делать с вашим кодом.</div>
                            </div>

                            <!-- Owners / Collaborators -->
                            <div class="mb-4">
                                <label class="form-label fw-bold">Владельцы / Участники</label>
                                <div class="dropdown">
                                    <button class="btn btn-outline-secondary w-100 text-start d-flex justify-content-between align-items-center" type="button" data-bs-toggle="dropdown" aria-expanded="false">
                                        <span>Выберите участников...</span>
                                        <i class="bi bi-chevron-down"></i>
                                    </button>
                                    <div class="dropdown-menu w-100 p-2" style="max-height: 300px; overflow-y: auto;">
                                        <input type="text" class="form-control mb-2" placeholder="Поиск пользователей..." v-model="userSearch">
                                        <div v-if="filteredUsers.length === 0" class="text-muted text-center py-2 text-small">Никого не найдено</div>
                                        <div v-for="user in filteredUsers" :key="user.user_id" class="form-check dropdown-item p-2 rounded">
                                            <input class="form-check-input ms-0 me-2" type="checkbox" :value="user.user_id" :id="'user'+user.user_id" v-model="form.owners">
                                            <label class="form-check-label w-100 cursor-pointer" :for="'user'+user.user_id">
                                                {{ user.full_name || user.username }} <span class="text-muted small">({{ user.username }})</span>
                                            </label>
                                        </div>
                                    </div>
                                </div>
                                <!-- Selected Users Tags -->
                                <div class="mt-2 d-flex flex-wrap gap-2" v-if="selectedUsersList.length > 0">
                                    <span v-for="user in selectedUsersList" :key="user.user_id" class="badge bg-light text-dark border d-flex align-items-center">
                                        {{ user.full_name || user.username }}
                                        <button type="button" class="btn-close ms-2" style="font-size: 0.5em;" @click="removeOwner(user.user_id)"></button>
                                    </span>
                                </div>
                            </div>


                            <div class="d-flex justify-content-end gap-2 mt-4">
                                <router-link :to="{ name: 'RepositoryList' }" class="btn btn-outline-secondary">
                                    Отмена
                                </router-link>
                                <button type="submit" class="btn btn-success" :disabled="loading">
                                    <span v-if="loading" class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>
                                    Создать репозиторий
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
            </div>
        </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onMounted } from 'vue';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';
import { useRouter } from 'vue-router';
import { useToast } from 'vue-toastification';
import { GetAdminUsers } from '@/core/cms/adp/admin/js/GroupsPolitics';

const router = useRouter();
const toast = useToast();
const loading = ref(false);

const form = reactive({
    name: '',
    description: '',
    visibility: 'public', // Default to public
    license: 'none',
    owners: []
});

const users = ref([]);
const userSearch = ref('');

// Fetch users on mount
onMounted(async () => {
    try {
        const fetchedUsers = await GetAdminUsers();
        users.value = fetchedUsers || [];
    } catch (error) {
        console.error('Failed to load users', error);
        toast.error('Не удалось загрузить список пользователей');
    }
});

const filteredUsers = computed(() => {
    if (!userSearch.value) return users.value;
    const query = userSearch.value.toLowerCase();
    return users.value.filter(u => 
        (u.username && u.username.toLowerCase().includes(query)) ||
        (u.full_name && u.full_name.toLowerCase().includes(query))
    );
});

const selectedUsersList = computed(() => {
    return users.value.filter(u => form.owners.includes(u.user_id));
});

const removeOwner = (id) => {
    form.owners = form.owners.filter(ownerId => ownerId !== id);
};

const createRepo = async () => {
    if (!form.name.trim()) {
      toast.warning('Введите название');
      return;
    }

    loading.value = true;
    try {
        // Шлем ТОЛЬКО то, что есть в RepositoryCreateSerializer
        const payload = {
            name: form.name,
            description: form.description,
            initial_branch_name: 'main' // Добавь это поле
        };

        const response = await apiClient.post(versionManagementEndpoints.version_management.create, payload);
        
        // DRF возвращает данные объекта при успехе, а не поле success
        // Проверяем статус ответа через твой apiClient
        if (response) { 
            toast.success('Репозиторий успешно создан');
            router.push({ name: 'RepositoryList' });
        }
    } catch (error) {
        // Выведи ошибку бэка в консоль, чтобы увидеть, на какое поле он ругается
        console.error('Ошибка от Бэка:', error.response?.data);
        toast.error('Ошибка сервера: ' + JSON.stringify(error.response?.data));
    } finally {
        loading.value = false;
    }
};
</script>

<style scoped>
.repository-create-page {
    padding: 20px;
}
.cursor-pointer {
    cursor: pointer;
}
</style>
