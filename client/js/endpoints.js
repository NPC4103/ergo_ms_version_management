export const versionManagementEndpoints = {
    version_management: {
        list: 'version_management/repositories/list/',
        create: 'version_management/repositories/create/',
        retrieve: id => `version_management/repositories/${id}/`,
        update: id => `repositories/${id}/update/`,
        delete: id => `repositories/${id}/delete/`,
        commit_create: id => `repositories/${id}/commits/create/`,
        commits_list: id => `repositories/${id}/commits/`,
        commit_retrieve: (id, hash) => `repositories/${id}/commits/${hash}/`,
        commit_diff: (id, hash) => `repositories/${id}/commits/${hash}/diff/`,
        clone: id => `repositories/${id}/clone/`,
        push: id => `repositories/${id}/push/`
    }
};

