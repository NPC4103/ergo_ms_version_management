import argparse
import subprocess
import sys
from pathlib import Path

from modules.version_management.api.view import three_way_merge


def _run_git_command(args, cwd):
    result = subprocess.run(
        ["git"] + args,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout.strip()


def _get_file_content_at(ref, file_path, cwd):
    try:
        output = _run_git_command(["show", f"{ref}:{file_path}"], cwd=cwd)
    except RuntimeError:
        # Если файла нет в этой ревизии, считаем содержимое пустым
        return ""
    return output


def main():
    parser = argparse.ArgumentParser(
        description="Выполнить трёхсторонний merge файла между двумя ветками с использованием git merge-base."
    )
    parser.add_argument("local_branch", help="Имя локальной ветки (CURRENT)")
    parser.add_argument("remote_branch", help="Имя удалённой ветки (INCOMING)")
    parser.add_argument("file_path", help="Путь к файлу относительно корня git‑репозитория")
    parser.add_argument(
        "--repo-root",
        default=".",
        help="Путь к корню git‑репозитория (по умолчанию текущая директория)",
    )

    args = parser.parse_args()

    repo_root = Path(args.repo_root).resolve()

    try:
        merge_base = _run_git_command(
            ["merge-base", args.local_branch, args.remote_branch],
            cwd=repo_root,
        )
    except RuntimeError as exc:
        print(f"Ошибка при определении merge-base: {exc}", file=sys.stderr)
        sys.exit(1)

    base_text = _get_file_content_at(merge_base, args.file_path, cwd=repo_root)
    local_text = _get_file_content_at(args.local_branch, args.file_path, cwd=repo_root)
    remote_text = _get_file_content_at(args.remote_branch, args.file_path, cwd=repo_root)

    merged = three_way_merge(base_text, local_text, remote_text)
    sys.stdout.write(merged)


if __name__ == "__main__":
    main()

