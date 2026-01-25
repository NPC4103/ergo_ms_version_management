from django.urls import include, path
from rest_framework.routers import DefaultRouter
from .view import RepositoryViewSet, BranchViewSet, CollaboratorViewSet

app_name = "version_management"

router = DefaultRouter()
router.register(r"repositories", RepositoryViewSet, basename="version-management-repository")
router.register(r'branches', BranchViewSet)
router.register(r"collaborators", CollaboratorViewSet, basename="version-management-repository-collaborator")


urlpatterns = [
    path("", include(router.urls)),
]