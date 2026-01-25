REST_FRAMEWORK = {
    'DEFAULT_PERMISSION_CLASSES': [
        # 'rest_framework.permissions.IsAuthenticated',  # вкл. Аутентификацию
        'rest_framework.permissions.AllowAny',  # выкл. Аутентификацию
    ],
    'DEFAULT_AUTHENTICATION_CLASSES': [
        # ЗАКОММЕНТИРУЙТЕ ВСЕ строки ниже, если надо откл. Аутентификацию:
        # 'rest_framework.authentication.SessionAuthentication',
        # 'rest_framework.authentication.BasicAuthentication',
        # 'rest_framework.authentication.TokenAuthentication',
    ]
}