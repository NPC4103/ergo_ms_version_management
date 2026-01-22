from django.urls import include, path
from rest_framework.routers import DefaultRouter
from .view import RepositoryViewSet, BranchViewSet

app_name = "version_management"

router = DefaultRouter()
router.register(r"repositories", RepositoryViewSet, basename="version-management-repository")
router.register(r'branches', BranchViewSet)

urlpatterns = [
    path("", include(router.urls)),
]