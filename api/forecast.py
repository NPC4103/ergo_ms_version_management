"""
Модуль прогнозирования роста репозитория.

Строит временные ряды из истории коммитов и прогнозирует
будущий рост на основе линейной регрессии и скользящего среднего.
"""

import json
from pathlib import Path
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import Dict, List, Any, Optional
from collections import defaultdict


@dataclass
class DailyStats:
    """Ежедневная статистика изменений."""
    date: str
    bytes_added: int = 0
    bytes_deleted: int = 0
    files_added: int = 0
    files_deleted: int = 0
    files_modified: int = 0
    commits_count: int = 0
    net_growth: int = 0
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class ForecastResult:
    """Результат прогнозирования."""
    moving_average_7d: int
    moving_average_30d: int
    daily_trend: float
    confidence: str
    forecast: List[Dict[str, Any]]
    
    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class CommitHistoryAnalyzer:
    """Анализатор истории коммитов для построения временных рядов."""
    
    def __init__(self, media_root: Path, repo_uuid: str):
        self.media_root = Path(media_root)
        self.repo_uuid = repo_uuid
        self.repo_path = self.media_root / 'version_management' / repo_uuid
        self.branches_path = self.repo_path / 'branches'
    
    def build_time_series(self, days: int = 90) -> List[Dict[str, Any]]:
        """
        Строит временной ряд ежедневной статистики за последние N дней.
        
        Args:
            days: Количество дней для анализа
            
        Returns:
            Список словарей с ежедневной статистикой
        """
        # Инициализируем словарь для всех дней
        daily_stats: Dict[str, DailyStats] = {}
        today = datetime.now().date()
        
        for i in range(days):
            date = today - timedelta(days=days - 1 - i)
            date_str = date.isoformat()
            daily_stats[date_str] = DailyStats(date=date_str)
        
        if not self.branches_path.exists():
            return [s.to_dict() for s in daily_stats.values()]
        
        # Обходим все ветки и коммиты
        for branch_dir in self.branches_path.iterdir():
            if not branch_dir.is_dir():
                continue
            
            self._process_branch(branch_dir, daily_stats)
        
        # Вычисляем net_growth для каждого дня
        for stats in daily_stats.values():
            stats.net_growth = stats.bytes_added - stats.bytes_deleted
        
        # Возвращаем отсортированный список
        return [daily_stats[k].to_dict() for k in sorted(daily_stats.keys())]
    
    def _process_branch(self, branch_dir: Path, daily_stats: Dict[str, DailyStats]) -> None:
        """Обрабатывает ветку и её коммиты."""
        commits_path = branch_dir / 'commits'
        
        # Обрабатываем коммиты в папке commits/
        if commits_path.exists() and commits_path.is_dir():
            for commit_dir in commits_path.iterdir():
                if not commit_dir.is_dir():
                    continue
                self._process_commit(commit_dir, daily_stats)
        
        # Обрабатываем pending_commit если есть
        pending_path = branch_dir / 'pending_commit.json'
        if pending_path.exists():
            self._process_commit_json(pending_path, daily_stats)
        
        # Обрабатываем commit.json в корне ветки
        root_commit_path = branch_dir / 'commit.json'
        if root_commit_path.exists():
            self._process_commit_json(root_commit_path, daily_stats)
    
    def _process_commit(self, commit_dir: Path, daily_stats: Dict[str, DailyStats]) -> None:
        """Обрабатывает директорию коммита."""
        commit_json_path = commit_dir / 'commit.json'
        if commit_json_path.exists():
            self._process_commit_json(commit_json_path, daily_stats)
    
    def _process_commit_json(self, json_path: Path, daily_stats: Dict[str, DailyStats]) -> None:
        """Обрабатывает JSON файл коммита."""
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
        except (json.JSONDecodeError, IOError):
            return
        
        # Извлекаем дату коммита
        created_at = data.get('created_at') or data.get('pushed_at') or data.get('updated_at')
        if not created_at:
            return
        
        # Парсим дату
        try:
            date_str = created_at[:10]  # YYYY-MM-DD
        except (TypeError, IndexError):
            return
        
        if date_str not in daily_stats:
            return
        
        stats = daily_stats[date_str]
        stats.commits_count += 1
        
        # Обрабатываем файлы в коммите
        files = data.get('files', [])
        for file_info in files:
            if not isinstance(file_info, dict):
                continue
            
            action = file_info.get('action', 'modified')
            content = file_info.get('content', '')
            
            # Вычисляем размер контента
            if isinstance(content, str):
                size = len(content.encode('utf-8'))
            else:
                size = 0
            
            if action == 'added':
                stats.bytes_added += size
                stats.files_added += 1
            elif action == 'deleted':
                stats.bytes_deleted += size
                stats.files_deleted += 1
            else:  # modified
                stats.bytes_added += size
                stats.files_modified += 1


def calculate_forecast(time_series: List[Dict], forecast_days: int = 30) -> ForecastResult:
    """
    Прогнозирует рост репозитория на основе временного ряда.
    
    Использует:
    - Скользящее среднее (7 и 30 дней)
    - Линейную регрессию для определения тренда
    
    Args:
        time_series: Список ежедневной статистики
        forecast_days: Количество дней для прогноза
        
    Returns:
        ForecastResult с прогнозом
    """
    if len(time_series) < 7:
        return ForecastResult(
            moving_average_7d=0,
            moving_average_30d=0,
            daily_trend=0.0,
            confidence='insufficient_data',
            forecast=[]
        )
    
    # Извлекаем ежедневный прирост
    daily_growth = [day.get('net_growth', 0) for day in time_series]
    n = len(daily_growth)
    
    # Скользящее среднее за 7 дней
    window_7 = min(7, n)
    ma_7d = sum(daily_growth[-window_7:]) / window_7
    
    # Скользящее среднее за 30 дней
    window_30 = min(30, n)
    ma_30d = sum(daily_growth[-window_30:]) / window_30
    
    # Линейная регрессия для определения тренда
    # y = ax + b, где a - slope (тренд)
    x_values = list(range(n))
    x_mean = sum(x_values) / n
    y_mean = sum(daily_growth) / n
    
    numerator = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_values, daily_growth))
    denominator = sum((x - x_mean) ** 2 for x in x_values)
    
    slope = numerator / denominator if denominator != 0 else 0
    intercept = y_mean - slope * x_mean
    
    # Определяем уровень уверенности
    if n < 14:
        confidence = 'low'
    elif n < 30:
        confidence = 'medium'
    elif n < 90:
        confidence = 'high'
    else:
        confidence = 'very_high'
    
    # Генерируем прогноз
    forecast = []
    last_date_str = time_series[-1].get('date', '')
    
    try:
        last_date = datetime.fromisoformat(last_date_str).date()
    except (ValueError, TypeError):
        last_date = datetime.now().date()
    
    cumulative_growth = sum(daily_growth)
    
    for i in range(1, forecast_days + 1):
        date = last_date + timedelta(days=i)
        
        # Прогноз на основе тренда + скользящего среднего
        predicted_trend = slope * (n + i) + intercept
        predicted_ma = ma_7d + (slope * i)
        
        # Взвешенное среднее между трендом и скользящим средним
        predicted = (predicted_trend * 0.4 + predicted_ma * 0.6)
        
        cumulative_growth += predicted
        
        forecast.append({
            'date': date.isoformat(),
            'predicted_daily_growth': int(predicted),
            'predicted_cumulative': int(cumulative_growth),
        })
    
    return ForecastResult(
        moving_average_7d=int(ma_7d),
        moving_average_30d=int(ma_30d),
        daily_trend=round(slope, 2),
        confidence=confidence,
        forecast=forecast
    )


def format_bytes(size_bytes: int) -> str:
    """Форматирует размер в человекочитаемый формат."""
    size = float(abs(size_bytes))
    sign = '-' if size_bytes < 0 else ''
    
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if size < 1024:
            return f"{sign}{size:.2f} {unit}"
        size /= 1024
    return f"{sign}{size:.2f} PB"


def analyze_repository_forecast(
    media_root: str,
    repo_uuid: str,
    history_days: int = 90,
    forecast_days: int = 30
) -> Dict[str, Any]:
    """
    Основная функция для анализа и прогнозирования роста репозитория.
    
    Args:
        media_root: Путь к директории media
        repo_uuid: UUID репозитория
        history_days: Количество дней истории для анализа
        forecast_days: Количество дней для прогноза
        
    Returns:
        Словарь с временным рядом, прогнозом и сводкой
    """
    analyzer = CommitHistoryAnalyzer(Path(media_root), repo_uuid)
    time_series = analyzer.build_time_series(days=history_days)
    forecast_result = calculate_forecast(time_series, forecast_days)
    
    # Вычисляем итоговую статистику
    total_added = sum(d.get('bytes_added', 0) for d in time_series)
    total_deleted = sum(d.get('bytes_deleted', 0) for d in time_series)
    total_commits = sum(d.get('commits_count', 0) for d in time_series)
    total_files_added = sum(d.get('files_added', 0) for d in time_series)
    total_files_deleted = sum(d.get('files_deleted', 0) for d in time_series)
    total_files_modified = sum(d.get('files_modified', 0) for d in time_series)
    net_growth = total_added - total_deleted
    
    # Средние значения
    active_days = sum(1 for d in time_series if d.get('commits_count', 0) > 0)
    avg_daily_growth = net_growth // history_days if history_days > 0 else 0
    
    # Прогнозируемый рост
    projected_growth = 0
    if forecast_result.forecast:
        projected_growth = forecast_result.forecast[-1].get('predicted_cumulative', 0) - net_growth
    
    return {
        'time_series': time_series,
        'forecast': forecast_result.to_dict(),
        'summary': {
            'history_days': history_days,
            'forecast_days': forecast_days,
            'active_days': active_days,
            'total_commits': total_commits,
            'total_bytes_added': total_added,
            'total_bytes_added_human': format_bytes(total_added),
            'total_bytes_deleted': total_deleted,
            'total_bytes_deleted_human': format_bytes(total_deleted),
            'net_growth': net_growth,
            'net_growth_human': format_bytes(net_growth),
            'avg_daily_growth': avg_daily_growth,
            'avg_daily_growth_human': format_bytes(avg_daily_growth),
            'total_files_added': total_files_added,
            'total_files_deleted': total_files_deleted,
            'total_files_modified': total_files_modified,
            'projected_30d_growth': projected_growth,
            'projected_30d_growth_human': format_bytes(projected_growth),
        }
    }
