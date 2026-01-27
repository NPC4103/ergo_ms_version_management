const API_PREFIX = 'version_management';

export const versionManagementEndpoints = {
    repositories: {
        list: `${API_PREFIX}/repositories/`,
        create: `${API_PREFIX}/repositories/`,
        retrieve: (publicId) =>
            `${API_PREFIX}/repositories/${publicId}/`,
        update: (publicId) =>
            `${API_PREFIX}/repositories/${publicId}/`,
        delete: (publicId) =>
            `${API_PREFIX}/repositories/${publicId}/`,

        // custom actions
        setDefaultBranch: (publicId) =>
            `${API_PREFIX}/repositories/${publicId}/set_default_branch/`,
        branches: (publicId) =>
            `${API_PREFIX}/repositories/${publicId}/branches/`,
        collaborators: (publicId) =>
            `${API_PREFIX}/repositories/${publicId}/collaborators/`,

        // commits
        commitsList: (publicId) =>
            `${API_PREFIX}/repositories/${publicId}/commits/`,
        commitCreate: (publicId) =>
            `${API_PREFIX}/repositories/${publicId}/commits/create/`,
        commitRetrieve: (publicId, commitHash) =>
            `${API_PREFIX}/repositories/${publicId}/commits/${commitHash}/`,
        commitDiff: (publicId, commitHash) =>
            `${API_PREFIX}/repositories/${publicId}/commits/${commitHash}/diff/`,

        // branch files
        branchFiles: (publicId, branchName) =>
            `${API_PREFIX}/repositories/${publicId}/branches/${branchName}/files/`,
    },

    branches: {
        list: `${API_PREFIX}/branches/`,
        create: `${API_PREFIX}/branches/`,
        retrieve: (id) =>
            `${API_PREFIX}/branches/${id}/`,
        update: (id) =>
            `${API_PREFIX}/branches/${id}/`,
        delete: (id) =>
            `${API_PREFIX}/branches/${id}/`,

        // custom actions
        setDefaultGlobal: `${API_PREFIX}/branches/set_default/`,
        makeDefault: (id) =>
            `${API_PREFIX}/branches/${id}/make_default/`,
    },

    collaborators: {
        list: `${API_PREFIX}/collaborators/`,
        create: `${API_PREFIX}/collaborators/`,
        retrieve: (id) =>
            `${API_PREFIX}/collaborators/${id}/`,
        update: (id) =>
            `${API_PREFIX}/collaborators/${id}/`,
        delete: (id) =>
            `${API_PREFIX}/collaborators/${id}/`,

        // custom actions
        byRepository: `${API_PREFIX}/collaborators/by_repository/`,
    },
};
