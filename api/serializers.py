# serializers.py
from email.policy import default
from nt import write
from tabnanny import check
from urllib3 import request
from django.template import context
from rest_framework import serializers
from .models import Repository, Branch, Collaborator


class RepositorySerializer(serializers.ModelSerializer):
    """Сериализатор для чтения репозитория"""
    branch_count = serializers.SerializerMethodField()
    default_branch = serializers.SerializerMethodField()
    public_id = serializers.UUIDField(read_only=True)
    is_editable = serializers.SerializerMethodField()
    user_role = serializers.SerializerMethodField()
    collaborators_count  = serializers.SerializerMethodField()

    class Meta:
        model = Repository
        fields = [
            'public_id',
            'name', 
            'description',
            'is_private',
            'is_read_only',
            'owner_id',
            'branch_count',
            'default_branch',
            'is_editable',
            'user_role',
            'collaborators_count',
            'created_at',
            'updated_at'
        ]
        read_only_fields = ['public_id', 'created_at', 'updated_at', 'owner_id']
    
    def get_branch_count(self, obj):
        """Количество веток в репозитории (для информации)"""
        return obj.branches.count()
    
    def get_default_branch(self, obj):
        """Информация о ветке по умолчанию"""
        default_branch = obj.branches.filter(is_default=True).first()
        if default_branch:
            return {
                'id': default_branch.id,
                'name': default_branch.name
            }
        return None
    
    def get_is_editable(self, obj):
        """Может ли текущий пользователь редактировать репозиторий"""
        request = self.context.get('request')
        if request and request.user:
            return obj.can_user_modify(request.user.id)
        return False

    def get_user_role(self, obj):
        """Роль текущего пользователя в репозитории"""
        request = self.context.get('request')
        if request and request.user:
            return obj.get_user_role(request.user.id)
        return None

    def get_collaborators_count(self, obj):
        """Количество коллабораторов репозитория"""
        return obj.collaborators.count()

    def validate_name(self, value):
        """Простая валидация названия"""
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Название не может быть пустым")
        return value


class BranchSerializer(serializers.ModelSerializer):
    """Сериализатор для ветки (чтение)"""
    repository_name = serializers.CharField(source='repository.name', read_only=True)
    repository_public_id = serializers.UUIDField(source='repository.public_id', read_only=True)
    is_repository_editable = serializers.SerializerMethodField()

    class Meta:
        model = Branch
        fields = [
            'id',
            'name',
            'repository',
            'repository_public_id',
            'repository_name',
            'is_default',
            'is_repository_editable',
            'created_at'
        ]
        read_only_fields = ['id', 'created_at', 'repository_name', 'repository_public_id', 'is_default']
    
    def validate_name(self, value):
        """Простая валидация имени ветки"""
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Имя ветки не может быть пустым")
        return value

    def get_is_repository_editable(self, obj):
        """Можно ли редактировать родительский репозиторий"""
        request = self.context.get('request')
        if request and request.user:
            return obj.repository.can_user_modify(request.user.id)
        return False


class RepositoryCreateSerializer(serializers.ModelSerializer):
    """Сериализатор для создания репозитория (с первой веткой)"""
    initial_branch_name = serializers.CharField(
        default='main',
        required=False,
        help_text="Имя начальной ветки"
    )
    is_private = serializers.BooleanField(default=False, required=False)
    is_read_only = serializers.BooleanField(default=False, required=False)
    
    # Поля для аутентификации (для CLI/утилит)
    cli_username = serializers.CharField(
        required=False,
        write_only=True,
        help_text="Имя пользователя для аутентификации через CLI"
    )
    cli_password = serializers.CharField(
        required=False,
        write_only=True,
        help_text="Пароль для аутентификации через CLI"
    )

    class Meta:
        model = Repository
        fields = [
        'name', 
        'description', 
        'initial_branch_name', 
        'is_private', 
        'is_read_only',
        'cli_username',
        'cli_password'
        ]
    
    def validate(self, data):
        """Валидация с аутентификацией пользователя"""
        request = self.context.get('request')
        
        # Извлекаем данные аутентификации
        cli_username = data.pop('cli_username', None)
        cli_password = data.pop('cli_password', None)
        
        # Проверяем, каким способом будет аутентификация
        if cli_username or cli_password:
            # Если указан логин или пароль, проверяем что оба указаны
            if not (cli_username and cli_password):
                raise serializers.ValidationError({
                    'cli_credentials': 'Для аутентификации через CLI укажите и cli_username, и cli_password'
                })

        # Сохраняем в контексте для использования в create
        self.context['cli_username'] = cli_username
        self.context['cli_password'] = cli_password
        
        return data

    def create(self, validated_data):
        """Создание репозитория с первой веткой"""
        initial_branch_name = validated_data.pop('initial_branch_name', 'main')
        is_private = validated_data.pop('is_private', False)
        is_read_only = validated_data.pop('is_read_only', False)

        # Получаем данные аутентификации
        cli_username = self.context.get('cli_username')
        cli_password = self.context.get('cli_password')
        request = self.context.get('request')
        
        owner_id = None
        
        # Способ 1: Аутентификация через CLI (логин/пароль в теле запроса)
        if cli_username and cli_password:
            from django.contrib.auth import authenticate
            user = authenticate(username=cli_username, password=cli_password)
            if user is not None:
                owner_id = user.id
            else:
                raise serializers.ValidationError({
                    'cli_credentials': 'Неверные учетные данные'
                })
        
        # Способ 2: Стандартная аутентификация через request (для веб-интерфейса)
        elif request and request.user and request.user.is_authenticated:
            owner_id = request.user.id
        
        # Если ни один способ не сработал
        if owner_id is None:
            raise serializers.ValidationError({
                'auth': 'Требуется аутентификация. Для CLI укажите cli_username и cli_password'
            })

        # Создаем репозиторий с указанием владельца
        repository = Repository.objects.create(
            name=validated_data['name'],
            description=validated_data.get('description', ''),
            is_private=is_private,
            is_read_only=is_read_only,
            owner_id=owner_id
        )
        
        # Создаем первую ветку (автоматически дефолтная)
        Branch.objects.create(
            repository=repository,
            name=initial_branch_name,
            is_default=True
        )
        
        return repository


class CLIAuthMixin:
    """Миксин для добавления аутентификации через CLI (логин/пароль)"""
    
    # Добавляем поля аутентификации
    cli_username = serializers.CharField(required=False, write_only=True)
    cli_password = serializers.CharField(required=False, write_only=True)
    
    def _authenticate_cli_user(self, data):
        """Аутентификация пользователя из данных CLI"""
        request = self.context.get('request')
        
        # Извлекаем данные аутентификации
        cli_username = data.pop('cli_username', None)
        cli_password = data.pop('cli_password', None)
        
        # Проверяем, что оба поля указаны
        if cli_username or cli_password:
            if not (cli_username and cli_password):
                raise serializers.ValidationError({
                    'cli_credentials': 'Для аутентификации через CLI укажите и cli_username, и cli_password'
                })
        
        # Аутентификация через логин/пароль
        if cli_username and cli_password:
            from django.contrib.auth import authenticate
            user = authenticate(username=cli_username, password=cli_password)
            if user is not None:
                return user
            else:
                raise serializers.ValidationError({
                    'cli_credentials': 'Неверные учетные данные'
                })
        
        # Стандартная аутентификация через request
        elif request and request.user and request.user.is_authenticated:
            return request.user
        
        return None
    
    def validate(self, data):
        """Валидация с проверкой аутентификации"""
        user = self._authenticate_cli_user(data)
        if user is None:
            raise serializers.ValidationError({
                'auth': 'Требуется аутентификация. Для CLI укажите cli_username и cli_password'
            })
        
        # Сохраняем пользователя в контексте
        self.context['authenticated_user'] = user
        return data



class BranchCreateSerializer(CLIAuthMixin, serializers.Serializer):
    """Сериализатор для создания ветки"""
    repository_public_id = serializers.UUIDField(
        write_only=True,
        help_text="Public ID репозитория"
    )
    check_permissions = serializers.BooleanField(default=True, write_only=True, required=False)

    class Meta:
        model = Branch
        fields = [
        'name', 
        'repository_public_id', 
        'check_permissions',
        'cli_username',
        'cli_password'
        ]
    
    def validate(self, data):
        """Проверяем существование репозитория и права доступа"""
        # Вызываем аутентификацию из миксина
        data = super().validate(data)
        
        user = self.context.get('authenticated_user')
        if not user:
            raise serializers.ValidationError("Пользователь не аутентифицирован")
            
        try:
            repository = Repository.objects.get(public_id=data['repository_public_id'])
            
            # Проверяем права доступа
            check_permissions = data.get('check_permissions', True)
            if check_permissions and not repository.can_user_modify(user.id):
                raise serializers.ValidationError({
                    'repository_public_id': 'У вас недостаточно прав для создания ветки в этом репозитории'
                })

            data['repository'] = repository
            del data['repository_public_id']
            if 'check_permissions' in data:
                del data['check_permissions']
        except Repository.DoesNotExist:
            raise serializers.ValidationError({
                'repository_public_id': 'Репозиторий с таким public_id не найден'
            })
        return data
    
    def create(self, validated_data):
        """Создание ветки"""
        return Branch.objects.create(**validated_data)


class SetDefaultBranchSerializer(CLIAuthMixin, serializers.Serializer):
    """Сериализатор для установки ветки по умолчанию"""
    branch_id = serializers.IntegerField(required=False)
    repository_public_id = serializers.UUIDField(required=False)
    branch_name = serializers.CharField(required=False)
    check_permissions = serializers.BooleanField(default=True, required=False)

    def validate(self, data):
        """Проверяем, что передан один из вариантов идентификации"""

        data = super().validate(data)
        
        user = self.context.get('authenticated_user')
        if not user:
            raise serializers.ValidationError("Пользователь не аутентифицирован")

        branch_id = data.get('branch_id')
        repository_public_id = data.get('repository_public_id')
        branch_name = data.get('branch_name')
        check_permissions = data.get('check_permissions', True)

        # Вариант 1: По ID ветки
        if branch_id:
            try:
                branch = Branch.objects.get(id=branch_id)
                # Проверяем права доступа
                if check_permissions and not branch.repository.can_user_modify(user.id):
                    raise serializers.ValidationError({
                        'branch_id': 'У вас недостаточно прав для изменения этой ветки'
                    })
                data['branch'] = branch
                return data
            except Branch.DoesNotExist:
                raise serializers.ValidationError({
                    'branch_id': 'Ветка не найдена'
                })
        
        # Вариант 2: По public_id репозитория и имени ветки
        elif repository_public_id and branch_name:
            try:
                repository = Repository.objects.get(public_id=repository_public_id)
                branch = Branch.objects.get(repository=repository, name=branch_name)

                # Проверяем права доступа
                if check_permissions and not repository.can_user_modify(user.id):
                    raise serializers.ValidationError({
                        'branch_name': 'У вас недостаточно прав для изменения этой ветки'
                    })

                data['branch'] = branch
                return data
            except Repository.DoesNotExist:
                raise serializers.ValidationError({
                    'repository_public_id': 'Репозиторий не найден'
                })
            except Branch.DoesNotExist:
                raise serializers.ValidationError({
                    'branch_name': 'Ветка не найдена в репозитории'
                })
        
        # Если не передан ни один вариант
        raise serializers.ValidationError(
            "Необходимо указать либо branch_id, либо repository_public_id и branch_name"
        )
    
    def save(self):
        """Устанавливаем ветку по умолчанию"""
        branch = self.validated_data['branch']
        Branch.set_default_branch(branch)
        return branch

class BranchListSerializer(serializers.ModelSerializer):
    """Упрощенный сериализатор для списка веток"""
    repository_public_id = serializers.UUIDField(source='repository.public_id', read_only=True)
    is_repository_editable = serializers.SerializerMethodField()

    class Meta:
        model = Branch
        fields = ['id', 'name', 'repository_public_id', 'is_default', 'is_repository_editable', 'created_at']

    def get_is_repository_editable(self, obj):
        """Можно ли редактировать родительский репозиторий"""
        request = self.context.get('request')
        if request and request.user:
            return obj.repository.can_user_modify(request.user.id)
        return False


class RepositoryUpdateSerializer(serializers.ModelSerializer):
    """Сериализатор для обновления репозитория"""
    class Meta:
        model = Repository
        fields = ['name', 'description', 'is_private', 'is_read_only']
    
    def validate_name(self, value):
        """Простая валидация при обновлении"""
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Название не может быть пустым")
        return value

    def validate(self, data):
        """Проверяем, что пользователь имеет право на обновление"""
        request = self.context.get('request')
        instance = self.instance
        
        if request and instance and not instance.can_user_modify(request.user.id):
            raise serializers.ValidationError("У вас недостаточно прав для обновления этого репозитория")
        
        return data

class CollaboratorSerializer(serializers.ModelSerializer):
    """Сериализатор для коллаборатора"""
    user_display_name = serializers.SerializerMethodField()
    
    class Meta:
        model = Collaborator
        fields = ['id', 'user_id', 'user_display_name', 'role', 'added_at']
        read_only_fields = ['id', 'added_at']
    
    def get_user_display_name(self, obj):
        """Получаем отображаемое имя пользователя (можно расширить)"""
        return f"User #{obj.user_id}"
    
    def validate(self, data):
        """Валидация при создании/обновлении коллаборатора"""
        request = self.context.get('request')
        repository_id = self.context.get('repository_id')
        
        if not request or not request.user:
            raise serializers.ValidationError("Требуется аутентификация")
        
        # Получаем репозиторий
        try:
            repository = Repository.objects.get(id=repository_id)
        except Repository.DoesNotExist:
            raise serializers.ValidationError("Репозиторий не найден")
        
        # Проверяем, что текущий пользователь - владелец или администратор
        if request.user.id != repository.owner_id:
            collaborator = repository.collaborators.filter(
                user_id=request.user.id, 
                role='admin'
            ).first()
            if not collaborator:
                raise serializers.ValidationError("Только владелец или администратор может управлять коллабораторами")
        
        # Проверяем, что не добавляем владельца как коллаборатора
        user_id = data.get('user_id')
        if user_id == repository.owner_id:
            raise serializers.ValidationError({
                'user_id': 'Владелец репозитория не может быть добавлен как коллаборатор'
            })
        
        return data
    
    def create(self, validated_data):
        """Создание коллаборатора"""
        repository_id = self.context.get('repository_id')
        repository = Repository.objects.get(id=repository_id)
        
        return Collaborator.objects.create(
            repository=repository,
            **validated_data
        )


class CollaboratorCreateSerializer(CLIAuthMixin, serializers.Serializer):
    """Сериализатор для добавления коллаборатора"""
    user_id = serializers.IntegerField(required=True)
    role = serializers.ChoiceField(choices=Collaborator.ROLE_CHOICES, default='write')
    
    repository_public_id = serializers.UUIDField(required=True)


    # Вызываем аутентификацию из миксина
    def validate(self, data):
        """Валидация данных"""
        # Вызываем аутентификацию из миксина
        data = super().validate(data)
        
        user = self.context.get('authenticated_user')
        if not user:
            raise serializers.ValidationError("Пользователь не аутентифицирован")
        
        # Получаем репозиторий
        try:
            repository = Repository.objects.get(public_id=data['repository_public_id'])
        except Repository.DoesNotExist:
            raise serializers.ValidationError("Репозиторий не найден")
        
        # Проверяем права пользователя
        if user.id != repository.owner_id:
            admin_collaborator = repository.collaborators.filter(
                user_id=user.id,
                role='admin'
            ).first()
            if not admin_collaborator:
                raise serializers.ValidationError("Только владелец или администратор может добавлять коллабораторов")
        
        # Проверяем, что пользователь не является владельцем
        if data['user_id'] == repository.owner_id:
            raise serializers.ValidationError({
                'user_id': 'Владелец репозитория не может быть добавлен как коллаборатор'
            })
        
        # Проверяем, что пользователь еще не является коллаборатором
        if repository.collaborators.filter(user_id=data['user_id']).exists():
            raise serializers.ValidationError({
                'user_id': 'Пользователь уже является коллаборатором этого репозитория'
            })
        
        data['repository'] = repository
        return data