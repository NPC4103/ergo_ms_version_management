# view.py
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.shortcuts import get_object_or_404

from .models import Repository, Branch
from .serializers import (
    RepositorySerializer,
    RepositoryCreateSerializer,
    RepositoryUpdateSerializer,
    BranchSerializer,
    BranchCreateSerializer,
    SetDefaultBranchSerializer
)


class RepositoryViewSet(viewsets.ModelViewSet):
    """
    ViewSet для управления репозиториями.
    """
    queryset = Repository.objects.all()
    
    def get_serializer_class(self):
        """Выбираем сериализатор в зависимости от действия"""
        if self.action == 'create':
            return RepositoryCreateSerializer
        elif self.action in ['update', 'partial_update']:
            return RepositoryUpdateSerializer
        return RepositorySerializer
    
    @action(detail=True, methods=['post'])
    def set_default_branch(self, request, pk=None):
        """
        Установить ветку по умолчанию для репозитория.
        POST /repositories/{id}/set_default_branch/
        {
            "branch_id": 1
        }
        """
        repository = self.get_object()
        serializer = SetDefaultBranchSerializer(data=request.data)
        
        if serializer.is_valid():
            branch_id = serializer.validated_data['branch_id']
            
            # Находим ветку в этом репозитории
            branch = get_object_or_404(Branch, id=branch_id, repository=repository)
            
            # Устанавливаем как дефолтную
            Branch.set_default_branch(branch)
            
            return Response({
                'success': True,
                'message': f'Ветка "{branch.name}" установлена как ветка по умолчанию',
                'repository': self.get_serializer(repository).data  # Вернуть обновленные данные
            })
        
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


class BranchViewSet(viewsets.ModelViewSet):
    """
    ViewSet для управления ветками.
    """
    queryset = Branch.objects.all()
    
    def get_serializer_class(self):
        """Выбираем сериализатор в зависимости от действия"""
        if self.action == 'create':
            return BranchCreateSerializer
        return BranchSerializer
    
    def get_queryset(self):
        """Фильтрация веток по репозиторию если передан repository_id"""
        queryset = super().get_queryset()
        repository_id = self.request.query_params.get('repository_id')
        
        if repository_id:
            queryset = queryset.filter(repository_id=repository_id)
        
        return queryset