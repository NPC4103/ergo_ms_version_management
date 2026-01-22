<template>
  <div class="repository-list-page">
    <div class="header d-flex justify-content-between align-items-center mb-4">
      <h1>Репозитории</h1>
      <router-link :to="{ name: 'RepositoryCreate' }" class="btn btn-primary d-flex align-items-center gap-2">
        <i class="bi bi-plus-lg"></i> Создать репозиторий
      </router-link>
    </div>

    <!-- Toolbar: Search and Sort -->
    <div class="row g-3 mb-4">
      <div class="col-md-8">
        <div class="input-group">
          <span class="input-group-text bg-transparent border-end-0"><i class="bi bi-search"></i></span>
          <input 
            type="text" 
            class="form-control border-start-0 ps-0" 
            v-model="params.search" 
            @input="debounceSearch" 
            placeholder="Поиск репозиториев..."
          >
        </div>
      </div>
      <div class="col-md-4">
        <select class="form-select" v-model="selectedSort" @change="handleSortChange">
            <option value="created_at_desc">Сначала новые</option>
            <option value="created_at_asc">Сначала старые</option>
            <option value="updated_at_desc">Недавно обновленные</option>
            <option value="name_asc">По имени (А-Я)</option>
            <option value="name_desc">По имени (Я-А)</option>
        </select>
      </div>
    </div>

    <!-- Repository Grid -->
    <div v-if="loading && rows.length === 0" class="text-center py-5">
        <div class="spinner-border text-primary" role="status">
            <span class="visually-hidden">Загрузка...</span>
        </div>
    </div>

    <div v-else-if="rows.length > 0" class="row row-cols-1 row-cols-md-2 row-cols-xl-3 g-4">
        <div class="col" v-for="repo in rows" :key="repo.id">
            <div class="card h-100 shadow-sm border-0 repo-card">
                <div class="card-body d-flex flex-column">
                    <div class="d-flex justify-content-between align-items-start mb-2">
                        <h5 class="card-title text-primary fw-bold mb-0 text-truncate" :title="repo.name">
                            {{ repo.name }}
                        </h5>
                        <div class="dropdown">
                             <button class="btn btn-link text-muted p-0" type="button" data-bs-toggle="dropdown" aria-expanded="false">
                                <i class="bi bi-three-dots-vertical"></i>
                            </button>
                            <ul class="dropdown-menu dropdown-menu-end">
                                <li>
                                    <router-link :to="{ name: 'RepositoryDetail', params: { id: repo.id } }" class="dropdown-item">
                                        Открыть
                                    </router-link>
                                </li>
                                <li><hr class="dropdown-divider"></li>
                                <li>
                                    <button class="dropdown-item text-danger" @click="deleteRepo(repo.id)">
                                        Удалить
                                    </button>
                                </li>
                            </ul>
                        </div>
                    </div>
                    
                    <p class="card-text text-muted flex-grow-1 small repo-desc">
                        {{ repo.description || 'Нет описания' }}
                    </p>
                    
                    <div class="mt-3 pt-3 border-top">
                        <div class="d-flex justify-content-between text-muted small">
                            <span><i class="bi bi-calendar3 me-1"></i> {{ formatDate(repo.created_at) }}</span>
                            <span v-if="repo.updated_at" title="Обновлено"><i class="bi bi-clock-history me-1"></i> {{ formatDate(repo.updated_at) }}</span>
                        </div>
                    </div>
                </div>
                <div class="card-footer bg-transparent border-0 pb-3 pt-0">
                     <router-link :to="{ name: 'RepositoryDetail', params: { id: repo.id } }" class="btn btn-outline-primary w-100 btn-sm">
                        Перейти к репозиторию
                    </router-link>
                </div>
            </div>
        </div>
    </div>

    <div v-else class="text-center py-5 text-muted">
        <i class="bi bi-folder2-open display-4 mb-3 d-block"></i>
        <p class="lead">Репозитории не найдены</p>
    </div>

    <!-- Pagination -->
    <div v-if="totalPages > 1" class="d-flex justify-content-center mt-5">
        <nav aria-label="Page navigation">
            <ul class="pagination">
                <li class="page-item" :class="{ disabled: params.current_page === 1 }">
                    <button class="page-link" @click="changePage(params.current_page - 1)" aria-label="Previous">
                        <span aria-hidden="true">&laquo;</span>
                    </button>
                </li>
                
                <li class="page-item disabled">
                    <span class="page-link">
                        Страница {{ params.current_page }} из {{ totalPages }}
                    </span>
                </li>

                <li class="page-item" :class="{ disabled: params.current_page === totalPages }">
                    <button class="page-link" @click="changePage(params.current_page + 1)" aria-label="Next">
                        <span aria-hidden="true">&raquo;</span>
                    </button>
                </li>
            </ul>
        </nav>
    </div>

  </div>
</template>

<script setup>
import { ref, onMounted, reactive, computed } from 'vue';
import { apiClient } from '@/js/api/manager';
import { versionManagementEndpoints } from '../js/endpoints';
import { useToast } from 'vue-toastification';

const toast = useToast();
const loading = ref(false);
const totalRows = ref(0);
const rows = ref([]);

// Combined sort state to match dropdown UI
const selectedSort = ref('created_at_desc');

const params = reactive({
    current_page: 1,
    pagesize: 9, // Grid friendly number
    search: '',
    sort_column: 'created_at',
    sort_direction: 'desc'
});

const totalPages = computed(() => Math.ceil(totalRows.value / params.pagesize));

const handleSortChange = () => {
    const [column, direction] = selectedSort.value.rsplit('_', 1); // simple split won't work for created_at_desc
    // Custom parsing
    if (selectedSort.value === 'created_at_desc') { params.sort_column = 'created_at'; params.sort_direction = 'desc'; }
    else if (selectedSort.value === 'created_at_asc') { params.sort_column = 'created_at'; params.sort_direction = 'asc'; }
    else if (selectedSort.value === 'updated_at_desc') { params.sort_column = 'updated_at'; params.sort_direction = 'desc'; }
    else if (selectedSort.value === 'name_asc') { params.sort_column = 'name'; params.sort_direction = 'asc'; }
    else if (selectedSort.value === 'name_desc') { params.sort_column = 'name'; params.sort_direction = 'desc'; }
    
    params.current_page = 1;
    loadItems();
};

let searchTimeout = null;
const debounceSearch = () => {
    if (searchTimeout) clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => {
        params.current_page = 1;
        loadItems();
    }, 500);
};

const changePage = (page) => {
    if (page < 1 || page > totalPages.value) return;
    params.current_page = page;
    loadItems();
};

const loadItems = async () => {
    loading.value = true;
    try {
        const response = await apiClient.get(versionManagementEndpoints.version_management.list, {
            page: params.current_page,
            page_size: params.pagesize,
            search: params.search,
            ordering: (params.sort_direction === 'desc' ? '-' : '') + params.sort_column
        });
        
        if (response.success) {
            if (Array.isArray(response.data)) {
                 rows.value = response.data;
                 totalRows.value = response.data.length;
            } else {
                 rows.value = response.data.results || [];
                 totalRows.value = response.data.count || 0;
            }
        } else {
            toast.error(response.message || 'Ошибка загрузки репозиториев');
        }
    } catch (error) {
        toast.error('Ошибка сети');
        console.error(error);
    } finally {
        loading.value = false;
    }
};

const deleteRepo = async (id) => {
    if(!confirm('Вы уверены, что хотите удалить этот репозиторий?')) return;
    
    try {
        const response = await apiClient.delete(versionManagementEndpoints.version_management.delete(id));
        if (response.success) {
            toast.success('Репозиторий удален');
            loadItems();
        } else {
            toast.error(response.message || 'Ошибка удаления');
        }
    } catch (error) {
        toast.error('Ошибка удаления');
        console.error(error);
    }
};

const formatDate = (dateString) => {
    if (!dateString) return '';
    return new Date(dateString).toLocaleDateString('ru-RU', {
        day: 'numeric',
        month: 'short',
        year: 'numeric'
    });
};

onMounted(() => {
    loadItems();
});
</script>

<style scoped>
.repository-list-page {
    padding: 20px;
}

.repo-card {
    transition: transform 0.2s, box-shadow 0.2s;
}

.repo-card:hover {
    transform: translateY(-5px);
    box-shadow: 0 .5rem 1rem rgba(0,0,0,.15)!important;
}

.repo-desc {
    display: -webkit-box;
    -webkit-line-clamp: 3;
    -webkit-box-orient: vertical;
    overflow: hidden;
    text-overflow: ellipsis;
}
</style>

