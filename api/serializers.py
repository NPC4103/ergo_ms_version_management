from rest_framework import serializers

# Сериализатор для отдельных записей (файл или папка)
class FileSystemEntrySerializer(serializers.Serializer):
    name = serializers.CharField()
    is_directory = serializers.BooleanField()
    path = serializers.CharField()
    type = serializers.CharField()
    size = serializers.IntegerField(allow_null=True) # size может быть null для директорий