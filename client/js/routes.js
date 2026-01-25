export default {
    VersionManagement: {
        path: '/versionmanagement',
        name: 'VersionManagement',
        redirect: { name: 'RepositoryList' },
        component: '@/modules/version_management/client/ParentLayout.vue',
        meta: {
            title: 'Управление версиями',
            requiresAuth: true,
        },
        children: [
            {
                path: '',
                name: 'RepositoryList',
                component:
                    '@/modules/version_management/client/components/RepositoryList.vue',
                meta: {
                    title: 'Список репозиториев',
                },
            },
            {
                path: 'create',
                name: 'RepositoryCreate',
                component:
                    '@/modules/version_management/client/components/RepositoryCreate.vue',
                meta: {
                    title: 'Создание репозитория',
                },
            },
            {
                path: 'repo/:id',
                name: 'RepositoryDetail',
                component:
                    '@/modules/version_management/client/components/RepositoryDetail.vue',
                meta: {
                    title: 'Детали репозитория',
                },
            },
            {
                path: 'repo/:id/settings',
                name: 'RepositorySettings',
                component:
                    '@/modules/version_management/client/components/RepositorySettings.vue',
                meta: {
                    title: 'Настройки репозитория',
                },
            },
            {
                path: 'repo/:id/commits/create',
                name: 'CommitCreate',
                component:
                    '@/modules/version_management/client/components/CommitCreate.vue',
                meta: {
                    title: 'Создание коммита',
                },
            },
            {
                path: 'repo/:id/commits/:hash',
                name: 'CommitDetail',
                component:
                    '@/modules/version_management/client/components/CommitDetail.vue',
                meta: {
                    title: 'Детали коммита',
                },
            },
        ],
    },
};
