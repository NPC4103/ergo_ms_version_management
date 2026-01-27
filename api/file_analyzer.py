"""
Модуль анализа файлов репозиториев.

Рекурсивно обходит структуру коммитов и собирает статистику:
- Размеры файлов
- Типы файлов
- Частота изменений
- Кандидаты для холодного хранилища
"""

import os
import json
import mimetypes
from pathlib import Path
from datetime import datetime, timedelta
from collections import defaultdict
from dataclasses import dataclass, field, asdict
from typing import Dict, List, Optional, Any


# Порог для определения "тяжёлых" файлов (в байтах)
LARGE_FILE_THRESHOLD = 10 * 1024 * 1024  # 10 MB

# Порог неактивности для кандидатов в холодное хранилище (в днях)
COLD_STORAGE_INACTIVITY_DAYS = 90

# Расширения бинарных файлов
BINARY_EXTENSIONS = {
    '.exe', '.dll', '.so', '.dylib', '.bin', '.dat',
    '.zip', '.tar', '.gz', '.rar', '.7z', '.bz2',
    '.jpg', '.jpeg', '.png', '.gif', '.bmp', '.ico', '.webp', '.svg',
    '.mp3', '.mp4', '.avi', '.mkv', '.mov', '.wav', '.flac',
    '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx',
    '.pyc', '.pyo', '.class', '.o', '.obj',
}


@dataclass
class FileStats:
    """Статистика по отдельному файлу."""
    path: str
    size: int
    extension: str
    mime_type: Optional[str]
    is_binary: bool
    last_modified: str
    commit_count: int = 1
    first_seen: str = ""
    last_seen: str = ""


@dataclass
class RepositoryStats:
    """Общая статистика репозитория."""
    repo_uuid: str
    repo_name: str = ""
    total_size: int = 0
    total_files: int = 0
    total_commits: int = 0
    branches_count: int = 0
    
    # Статистика по типам файлов
    files_by_extension: Dict[str, int] = field(default_factory=dict)
    size_by_extension: Dict[str, int] = field(default_factory=dict)
    
    # Топ тяжёлых файлов
    largest_files: List[Dict[str, Any]] = field(default_factory=list)
    
    # Кандидаты для холодного хранилища
    cold_storage_candidates: List[Dict[str, Any]] = field(default_factory=list)
    
    # Статистика по веткам
    branches_stats: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    
    # Время анализа
    analyzed_at: str = ""
    analysis_duration_ms: int = 0

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class FileAnalyzer:
    """Анализатор файлов репозитория."""
    
    def __init__(self, media_root: Path, repo_uuid: str):
        self.media_root = Path(media_root)
        self.repo_uuid = repo_uuid
        self.repo_path = self.media_root / 'version_management' / repo_uuid
        self.branches_path = self.repo_path / 'branches'
        
        # Кэш для отслеживания файлов
        self._file_history: Dict[str, List[Dict]] = defaultdict(list)
        self._all_files: Dict[str, FileStats] = {}
    
    def analyze(self, repo_name: str = "") -> RepositoryStats:
        """
        Выполняет полный анализ репозитория.
        
        Returns:
            RepositoryStats с детализированной статистикой
        """
        start_time = datetime.now()
        
        stats = RepositoryStats(
            repo_uuid=self.repo_uuid,
            repo_name=repo_name,
            analyzed_at=start_time.isoformat()
        )
        
        if not self.branches_path.exists():
            return stats
        
        # Анализируем каждую ветку
        branches = [d for d in self.branches_path.iterdir() if d.is_dir()]
        stats.branches_count = len(branches)
        
        for branch_dir in branches:
            branch_name = branch_dir.name
            branch_stats = self._analyze_branch(branch_dir)
            stats.branches_stats[branch_name] = branch_stats
            
            # Агрегируем статистику
            stats.total_commits += branch_stats.get('commits_count', 0)
        
        # Собираем общую статистику по файлам
        self._aggregate_file_stats(stats)
        
        # Определяем кандидатов для холодного хранилища
        self._find_cold_storage_candidates(stats)
        
        # Вычисляем время анализа
        end_time = datetime.now()
        stats.analysis_duration_ms = int((end_time - start_time).total_seconds() * 1000)
        
        return stats
    
    def _analyze_branch(self, branch_dir: Path) -> Dict[str, Any]:
        """Анализирует отдельную ветку."""
        branch_stats = {
            'name': branch_dir.name,
            'commits_count': 0,
            'total_size': 0,
            'files_count': 0,
            'last_activity': None,
        }
        
        commits_path = branch_dir / 'commits'
        
        # Анализируем коммиты
        if commits_path.exists() and commits_path.is_dir():
            commits = [d for d in commits_path.iterdir() if d.is_dir()]
            branch_stats['commits_count'] = len(commits)
            
            for commit_dir in commits:
                self._analyze_commit(commit_dir, branch_dir.name, branch_stats)
        
        # Анализируем файлы в корне ветки (не в коммитах)
        for item in branch_dir.iterdir():
            if item.is_file() and item.name not in ['commit.json', 'pending_commit.json']:
                self._process_file(item, branch_dir.name, 'branch_root', branch_stats)
        
        return branch_stats
    
    def _analyze_commit(self, commit_dir: Path, branch_name: str, branch_stats: Dict) -> None:
        """Анализирует отдельный коммит."""
        commit_json_path = commit_dir / 'commit.json'
        commit_time = None
        
        # Читаем метаданные коммита
        if commit_json_path.exists():
            try:
                with open(commit_json_path, 'r', encoding='utf-8') as f:
                    commit_data = json.load(f)
                    commit_time = commit_data.get('created_at') or commit_data.get('pushed_at')
            except (json.JSONDecodeError, IOError):
                pass
        
        # Обновляем последнюю активность
        if commit_time:
            if not branch_stats['last_activity'] or commit_time > branch_stats['last_activity']:
                branch_stats['last_activity'] = commit_time
        
        # Анализируем файлы в коммите
        for item in commit_dir.rglob('*'):
            if item.is_file() and item.name != 'commit.json':
                self._process_file(item, branch_name, commit_dir.name, branch_stats, commit_time)
    
    def _process_file(
        self, 
        file_path: Path, 
        branch_name: str, 
        commit_hash: str, 
        branch_stats: Dict,
        commit_time: Optional[str] = None
    ) -> None:
        """Обрабатывает отдельный файл."""
        try:
            file_size = file_path.stat().st_size
            file_mtime = datetime.fromtimestamp(file_path.stat().st_mtime).isoformat()
        except OSError:
            return
        
        extension = file_path.suffix.lower()
        mime_type, _ = mimetypes.guess_type(str(file_path))
        is_binary = extension in BINARY_EXTENSIONS
        
        # Относительный путь от корня ветки
        try:
            rel_path = str(file_path.relative_to(self.branches_path / branch_name))
        except ValueError:
            rel_path = file_path.name
        
        # Уникальный ключ файла (путь в ветке)
        file_key = f"{branch_name}:{rel_path}"
        
        # Обновляем статистику ветки
        branch_stats['total_size'] += file_size
        branch_stats['files_count'] += 1
        
        # Отслеживаем историю файла
        self._file_history[file_key].append({
            'commit': commit_hash,
            'size': file_size,
            'time': commit_time or file_mtime,
        })
        
        # Обновляем или создаём статистику файла
        if file_key in self._all_files:
            existing = self._all_files[file_key]
            existing.commit_count += 1
            existing.size = max(existing.size, file_size)
            if commit_time:
                if not existing.first_seen or commit_time < existing.first_seen:
                    existing.first_seen = commit_time
                if not existing.last_seen or commit_time > existing.last_seen:
                    existing.last_seen = commit_time
        else:
            self._all_files[file_key] = FileStats(
                path=rel_path,
                size=file_size,
                extension=extension,
                mime_type=mime_type,
                is_binary=is_binary,
                last_modified=file_mtime,
                first_seen=commit_time or file_mtime,
                last_seen=commit_time or file_mtime,
            )
    
    def _aggregate_file_stats(self, stats: RepositoryStats) -> None:
        """Агрегирует статистику по всем файлам."""
        files_by_ext: Dict[str, int] = defaultdict(int)
        size_by_ext: Dict[str, int] = defaultdict(int)
        all_files_list: List[Dict] = []
        
        for file_key, file_stats in self._all_files.items():
            ext = file_stats.extension or 'no_extension'
            files_by_ext[ext] += 1
            size_by_ext[ext] += file_stats.size
            
            stats.total_size += file_stats.size
            stats.total_files += 1
            
            all_files_list.append({
                'path': file_stats.path,
                'size': file_stats.size,
                'extension': ext,
                'is_binary': file_stats.is_binary,
                'commit_count': file_stats.commit_count,
                'last_seen': file_stats.last_seen,
            })
        
        stats.files_by_extension = dict(files_by_ext)
        stats.size_by_extension = dict(size_by_ext)
        
        # Топ-10 самых больших файлов
        sorted_by_size = sorted(all_files_list, key=lambda x: x['size'], reverse=True)
        stats.largest_files = sorted_by_size[:10]
    
    def _find_cold_storage_candidates(self, stats: RepositoryStats) -> None:
        """Определяет кандидатов для миграции в холодное хранилище."""
        candidates = []
        now = datetime.now()
        threshold_date = now - timedelta(days=COLD_STORAGE_INACTIVITY_DAYS)
        
        for file_key, file_stats in self._all_files.items():
            is_candidate = False
            reasons = []
            
            # Критерий 1: Большой файл
            if file_stats.size >= LARGE_FILE_THRESHOLD:
                is_candidate = True
                reasons.append(f"large_file (>{LARGE_FILE_THRESHOLD // (1024*1024)}MB)")
            
            # Критерий 2: Бинарный файл значительного размера
            if file_stats.is_binary and file_stats.size >= 1024 * 1024:  # > 1MB
                is_candidate = True
                reasons.append("binary_file")
            
            # Критерий 3: Давно не изменялся
            try:
                last_seen_dt = datetime.fromisoformat(file_stats.last_seen.replace('Z', '+00:00'))
                if last_seen_dt.tzinfo:
                    last_seen_dt = last_seen_dt.replace(tzinfo=None)
                if last_seen_dt < threshold_date:
                    is_candidate = True
                    reasons.append(f"inactive (>{COLD_STORAGE_INACTIVITY_DAYS} days)")
            except (ValueError, AttributeError):
                pass
            
            if is_candidate:
                candidates.append({
                    'path': file_stats.path,
                    'size': file_stats.size,
                    'size_human': self._format_size(file_stats.size),
                    'extension': file_stats.extension,
                    'is_binary': file_stats.is_binary,
                    'last_seen': file_stats.last_seen,
                    'reasons': reasons,
                    'priority': self._calculate_priority(file_stats, reasons),
                })
        
        # Сортируем по приоритету (высший приоритет = больше причин для миграции)
        candidates.sort(key=lambda x: x['priority'], reverse=True)
        stats.cold_storage_candidates = candidates[:50]  # Топ-50 кандидатов
    
    def _calculate_priority(self, file_stats: FileStats, reasons: List[str]) -> int:
        """Вычисляет приоритет для миграции в холодное хранилище."""
        priority = 0
        
        # Больше причин = выше приоритет
        priority += len(reasons) * 10
        
        # Размер влияет на приоритет
        if file_stats.size >= 100 * 1024 * 1024:  # > 100MB
            priority += 50
        elif file_stats.size >= 50 * 1024 * 1024:  # > 50MB
            priority += 30
        elif file_stats.size >= 10 * 1024 * 1024:  # > 10MB
            priority += 20
        elif file_stats.size >= 1024 * 1024:  # > 1MB
            priority += 10
        
        # Бинарные файлы имеют больший приоритет
        if file_stats.is_binary:
            priority += 15
        
        return priority
    
    @staticmethod
    def _format_size(size_bytes: int) -> str:
        """Форматирует размер в человекочитаемый формат."""
        for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
            if size_bytes < 1024:
                return f"{size_bytes:.2f} {unit}"
            size_bytes /= 1024
        return f"{size_bytes:.2f} PB"


def analyze_repository(media_root: str, repo_uuid: str, repo_name: str = "") -> Dict[str, Any]:
    """
    Функция-обёртка для анализа репозитория.
    
    Args:
        media_root: Путь к директории media
        repo_uuid: UUID репозитория
        repo_name: Название репозитория (опционально)
    
    Returns:
        Словарь со статистикой репозитория
    """
    analyzer = FileAnalyzer(Path(media_root), repo_uuid)
    stats = analyzer.analyze(repo_name)
    return stats.to_dict()
