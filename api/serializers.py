# serializers.py
from rest_framework import serializers
from .models import Repository, Branch


class RepositorySerializer(serializers.ModelSerializer):
    """Сериализатор для чтения репозитория"""
    branch_count = serializers.SerializerMethodField()
    default_branch = serializers.SerializerMethodField()
    public_id = serializers.UUIDField(read_only=True)

    class Meta:
        model = Repository
        fields = [
            'public_id',
            'name', 
            'description',
            'branch_count',
            'default_branch',
            'created_at',
            'updated_at'
        ]
        read_only_fields = ['public_id', 'created_at', 'updated_at']
    
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

    class Meta:
        model = Branch
        fields = [
            'id',
            'name',
            'repository',
            'repository_public_id',
            'repository_name',
            'is_default',
            'created_at'
        ]
        read_only_fields = ['id', 'created_at', 'repository_name', 'repository_public_id', 'is_default']
    
    def validate_name(self, value):
        """Простая валидация имени ветки"""
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Имя ветки не может быть пустым")
        return value


class RepositoryCreateSerializer(serializers.ModelSerializer):
    """Сериализатор для создания репозитория (с первой веткой)"""
    initial_branch_name = serializers.CharField(
        default='main',
        required=False,
        help_text="Имя начальной ветки"
    )
    
    class Meta:
        model = Repository
        fields = ['name', 'description', 'initial_branch_name']
    
    def create(self, validated_data):
        """Создание репозитория с первой веткой"""
        initial_branch_name = validated_data.pop('initial_branch_name', 'main')
        
        # Создаем репозиторий
        repository = Repository.objects.create(
            name=validated_data['name'],
            description=validated_data.get('description', '')
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

    class Meta:
        model = Branch
        fields = ['name', 'repository_public_id']
    
    def validate(self, data):
        """Проверяем существование репозитория по public_id"""
        try:
            repository = Repository.objects.get(public_id=data['repository_public_id'])
            data['repository'] = repository
            del data['repository_public_id']
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

    def validate(self, data):
        """Проверяем, что передан один из вариантов идентификации"""
        branch_id = data.get('branch_id')
        repository_public_id = data.get('repository_public_id')
        branch_name = data.get('branch_name')
        
        # Вариант 1: По ID ветки
        if branch_id:
            try:
                branch = Branch.objects.get(id=branch_id)
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

    class Meta:
        model = Branch
        fields = ['id', 'name', 'repository_public_id', 'is_default', 'created_at']


class RepositoryUpdateSerializer(serializers.ModelSerializer):
    """Сериализатор для обновления репозитория"""
    class Meta:
        model = Repository
        fields = ['name', 'description']
    
    def validate_name(self, value):
        """Простая валидация при обновлении"""
        value = value.strip()
        if not value:
            raise serializers.ValidationError("Название не может быть пустым")
        return value