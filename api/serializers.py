# serializers.py
from email.policy import default
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
    
    class Meta:
        model = Repository
        fields = ['name', 'description', 'initial_branch_name', 'is_private', 'is_read_only']
    
    def create(self, validated_data):
        """Создание репозитория с первой веткой"""
        initial_branch_name = validated_data.pop('initial_branch_name', 'main')
        is_private = validated_data.pop('is_private', False)
        is_read_only = validated_data.pop('is_read_only', False)

        # Получаем екущего пользователя из контекста запроса
        request = self.context.get('request')
        if not request or not request.user:
            raise serializers.ValidationError("Требуется аутентификация")

        # Создаем репозиторий с указанием владельца
        repository = Repository.objects.create(
            name=validated_data['name'],
            description=validated_data.get('description', ''),
            is_private=is_private,
            is_read_only=is_read_only,
            owner_id=request.user.id
        )
        
        # Создаем первую ветку (автоматически дефолтная)
        Branch.objects.create(
            repository=repository,
            name=initial_branch_name,
            is_default=True
        )
        
        return repository


class BranchCreateSerializer(serializers.ModelSerializer):
    """Сериализатор для создания ветки"""
    repository_public_id = serializers.UUIDField(
        write_only=True,
        help_text="Public ID репозитория"
    )
    check_permissions = serializers.BooleanField(default=True, write_only=True, required=False)

    class Meta:
        model = Branch
        fields = ['name', 'repository_public_id', 'check_permissions']
    
    def validate(self, data):
        """Проверяем существование репозитория по public_id"""
        request = self.context.get('request')
        if not request or not request.user:
            raise serializers.ValidationError("Требуется аутентификация")
            
        try:
            repository = Repository.objects.get(public_id=data['repository_public_id'])
            
            # Проверяем права доступа, если требуется
            check_permissions = data.get('check_permissions', True)
            if check_permissions and not repository.can_user_modify(request.user.id):
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
        """Создание ветки (автоматически определяется is_default в модели)"""
        return Branch.objects.create(**validated_data)


class SetDefaultBranchSerializer(serializers.Serializer):
    """Сериализатор для установки ветки по умолчанию"""
    branch_id = serializers.IntegerField(required=False)
    repository_public_id = serializers.UUIDField(required=False)
    branch_name = serializers.CharField(required=False)
    check_permissions = serializers.BooleanField(default=True, required=False)

    def validate(self, data):
        """Проверяем, что передан один из вариантов идентификации"""
        request = self.context.get('request')
        if not request or not request.user:
            raise serializers.ValidationError("Требуется аутентификация")

        branch_id = data.get('branch_id')
        repository_public_id = data.get('repository_public_id')
        branch_name = data.get('branch_name')
        check_permissions = data.get('check_permissions', True)

        # Вариант 1: По ID ветки
        if branch_id:
            try:
                branch = Branch.objects.get(id=branch_id)
                # Проверяем права доступа
                if check_permissions and not branch.repository.can_user_modify(request.user.id):
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
                if check_permissions and not repository.can_user_modify(request.user.id):
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
    
    # def validate_branch_id(self, value):
    #     """Простая проверка существования ветки"""
    #     if not Branch.objects.filter(id=value).exists():
    #         raise serializers.ValidationError("Ветка не найдена")
    #     return value
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


class CollaboratorCreateSerializer(serializers.Serializer):
    """Сериализатор для добавления коллаборатора"""
    user_id = serializers.IntegerField(required=True)
    role = serializers.ChoiceField(choices=Collaborator.ROLE_CHOICES, default='write')
    
    def validate(self, data):
        """Валидация данных"""
        request = self.context.get('request')
        repository = self.context.get('repository')
        
        if not request or not request.user:
            raise serializers.ValidationError("Требуется аутентификация")
        
        # Проверяем права пользователя
        if request.user.id != repository.owner_id:
            admin_collaborator = repository.collaborators.filter(
                user_id=request.user.id,
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
        
        return data