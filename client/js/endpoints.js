export const versionManagementEndpoints = {
    version_management: {
        // Убираем /list/ и /create/ — в REST это один и тот же путь, 
        // просто GET (список) или POST (создание)
        list: 'version_management/repositories/', 
        create: 'version_management/repositories/', 
        
        retrieve: id => `version_management/repositories/${id}/`,
        
        // Тут тоже убирай /update/ и /delete/
        // Обновление — это PUT/PATCH на ID, удаление — это DELETE на ID
        update: id => `version_management/repositories/${id}/`,
        delete: id => `version_management/repositories/${id}/`,

        // С коммитами та же беда, если там тоже роутер:
        commits_list: id => `version_management/repositories/${id}/commits/`,
        commit_create: id => `version_management/repositories/${id}/commits/`,
        
        // Остальное (clone, push) — это @action, их пока не трогай, 
        // но проверь префикс version_management/
        clone: id => `version_management/repositories/${id}/clone/`,
        push: id => `version_management/repositories/${id}/push/`
    }
};