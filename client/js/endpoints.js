export const versionManagementEndpoints = {
    version_management: {
        list: '/version_management/repositories/', 
        create: '/version_management/repositories/',
        retrieve: id => `/version_management/repositories/${id}/`,
        update: id => `/version_management/repositories/${id}/`,
        delete: id => `/version_management/repositories/${id}/`,
        commits_list: id => `/version_management/repositories/${id}/commits/`,
        commit_create: id => `/version_management/repositories/${id}/commits/`,
    }
};