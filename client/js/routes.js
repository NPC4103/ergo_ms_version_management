export default {
    "VersionManagement": {
        "path": "/versionmanagement",
        "name": "VersionManagement",
        "redirect": { name: "RepositoryList" },
        "component": "@/modules/version_management/client/ParentLayout.vue",
        "children": [
            {
                "path": "",
                "name": "RepositoryList",
                "component": "@/modules/version_management/client/components/RepositoryList.vue",
                "meta": {
                    "title": "Список репозиториев"
                }
            },
            {
                "path": "create",
                "name": "RepositoryCreate",
                "component": "@/modules/version_management/client/components/RepositoryCreate.vue",
                "meta": {
                    "title": "Создание репозитория"
                }
            },
            {
                "path": ":id",
                "name": "RepositoryDetail",
                "component": "@/modules/version_management/client/components/RepositoryDetail.vue",
                "meta": {
                    "title": "Детали репозитория"
                }
            },
            {
                "path": ":id/settings",
                "name": "RepositorySettings",
                "component": "@/modules/version_management/client/components/RepositorySettings.vue",
                "meta": {
                    "title": "Настройки репозитория"
                }
            },
            {
                "path": ":id/commits/:hash",
                "name": "CommitDetail",
                "component": "@/modules/version_management/client/components/CommitDetail.vue",
                "meta": {
                    "title": "Детали коммита"
                }
            },
            {
                "path": ":id/commits/create",
                "name": "CommitCreate",
                "component": "@/modules/version_management/client/components/CommitCreate.vue",
                "meta": {
                    "title": "Создание коммита"
                }
            }
        ],
        "meta": {
            "title": "Управление версиями",
            "requiresAuth": true
        }
    },
}

