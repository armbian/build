#!/usr/bin/env python3
#
# SPDX-License-Identifier: GPL-2.0
#
# Copyright (c) 2013-2026 Igor Pecovnik, igor@armbian.com
#
# This file is a part of the Armbian Build Framework
# https://github.com/armbian/build/
#
"""
Parallel patch processing module for Armbian Build Framework using OverlayFS.

This module implements parallel processing of kernel/u-boot patches using overlayfs mounts.
It performs all the same operations as the serial implementation but with multiple workers.
"""

import logging
import os
import re
import shutil
import subprocess
import tempfile
import time
from concurrent.futures import ProcessPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Optional, List, Dict, Any
from multiprocessing import Manager, Queue

import git

from common.patching_config import PatchingConfig

log = logging.getLogger("patching_parallel")


@dataclass
class ParallelPatchResult:
    """Result of processing a single patch in parallel."""
    patch_index: int
    patch_id: str  # Identifies which patch this is
    success: bool
    commit_hash: Optional[str] = None
    rewritten_patch: Optional[str] = None
    problems: List[str] = field(default_factory=list)
    patch_output: str = ""
    error_message: Optional[str] = None
    memory_mb: Optional[float] = None
    diffstats: Optional[str] = None  # e.g., "(+2/-0)[1M]"
    files: Optional[str] = None  # e.g., "bes2600.c" or "file1.c, file2.h"
    commit_messages: List[str] = field(default_factory=list)  # Commit details from worker


@dataclass
class PatchWorkItem:
    """A single patch to be processed by a worker."""
    patch_index: int
    patch_id: str  # Unique identifier for the patch
    patch_data: Dict[str, Any]  # Serialized patch data
    mount_path: str  # OverlayFS mount point for this worker
    base_revision: str  # Git revision to reset to
    worker_branch_name: str  # Persistent branch name for this worker (all patches)
    is_first_in_sequence: bool = True  # Only first patch resets to base revision
    group_id: int = 0  # Which dependency group this patch belongs to (for reset detection)


class OverlayFSMount:
    """
    Context manager for OverlayFS mount operations.

    Handles creation, mounting, and cleanup of overlayfs mounts for parallel processing.
    """

    def __init__(self, lowerdir: str, mount_path: str, worker_id: int):
        """
        Initialize overlayfs mount.

        Args:
            lowerdir: Read-only base directory (linux source tree)
            mount_path: Where the overlayfs will be mounted
            worker_id: Worker identifier for directory naming
        """
        self.lowerdir = lowerdir
        self.mount_path = mount_path
        self.worker_id = worker_id
        self.upperdir = os.path.join(tempfile.gettempdir(), f"armbian-patch-worker-{worker_id}-upper")
        self.workdir = os.path.join(tempfile.gettempdir(), f"armbian-patch-worker-{worker_id}-work")
        self.is_mounted = False
        self.copied_git_metadata_dir: Optional[str] = None  # Track copied git metadata for cleanup

    def mount(self, fix_git_paths: bool = True) -> bool:
        """
        Create and mount the overlayfs.

        Args:
            fix_git_paths: If True, fix .git file paths for git worktrees

        Returns:
            True if successful, False otherwise
        """
        try:
            # Create upper and work directories
            os.makedirs(self.upperdir, exist_ok=True)
            os.makedirs(self.workdir, exist_ok=True)
            os.makedirs(self.mount_path, exist_ok=True)

            # Mount overlayfs
            cmd = [
                "mount",
                "-t", "overlay",
                "overlay",
                "-o", f"lowerdir={self.lowerdir},upperdir={self.upperdir},workdir={self.workdir}",
                self.mount_path
            ]

            result = subprocess.run(cmd, capture_output=True, text=True, check=False)

            if result.returncode != 0:
                log.error(f"Failed to mount overlayfs: {result.stderr}")
                return False

            self.is_mounted = True
            log.debug(f"Mounted overlayfs at {self.mount_path}")

            # Fix .git file paths if lowerdir is a git worktree
            # Git worktrees have .git files with relative paths that break through overlayfs
            if fix_git_paths:
                git_file = os.path.join(self.mount_path, '.git')
                if os.path.isfile(git_file):
                    try:
                        with open(git_file, 'r') as f:
                            content = f.read().strip()

                        if content.startswith('gitdir:'):
                            relative_path = content.split(':', 1)[1].strip()

                            # Resolve the absolute path from the ORIGINAL lowerdir (not mount point)
                            # This gives us the actual git worktree metadata directory
                            absolute_gitdir = os.path.normpath(os.path.join(self.lowerdir, relative_path))

                            # Copy the git metadata directory to a worker-specific location
                            # This prevents index lock contention between workers
                            if os.path.isdir(absolute_gitdir):
                                # Create worker-specific metadata directory
                                # Add -worker-{worker_id} suffix to the original directory name
                                git_metadata_parent = os.path.dirname(absolute_gitdir)
                                original_dirname = os.path.basename(absolute_gitdir)
                                copied_metadata_dir = os.path.join(git_metadata_parent, f"{original_dirname}-worker-{self.worker_id}")

                                # Copy the metadata directory
                                # Use shutil.copytree to preserve all git metadata
                                if os.path.exists(copied_metadata_dir):
                                    shutil.rmtree(copied_metadata_dir)
                                shutil.copytree(absolute_gitdir, copied_metadata_dir, symlinks=False)

                                # Store for cleanup
                                self.copied_git_metadata_dir = copied_metadata_dir

                                # Update .git file to point to the copied location
                                with open(git_file, 'w') as f:
                                    f.write(f"gitdir: {copied_metadata_dir}")

                                log.debug(f"Copied git metadata for worker {self.worker_id}: {absolute_gitdir} -> {copied_metadata_dir}")
                            else:
                                # Not a worktree, just fix the path
                                with open(git_file, 'w') as f:
                                    f.write(f"gitdir: {absolute_gitdir}")

                            log.debug(f"Fixed .git path in {self.mount_path}")
                    except Exception as e:
                        log.debug(f"Could not fix .git file: {e}")

            return True

        except Exception as e:
            log.error(f"Failed to create overlayfs mount: {e}")
            return False

    def unmount(self) -> bool:
        """
        Unmount the overlayfs and clean up directories.

        Returns:
            True if successful, False otherwise
        """
        # Unmount if mounted
        if self.is_mounted:
            try:
                result = subprocess.run(
                    ["umount", self.mount_path],
                    capture_output=True, text=True, check=False, timeout=5
                )
                if result.returncode != 0:
                    log.error(f"Failed to unmount {self.mount_path}: {result.stderr.strip()}")
                    log.error("Mount still active after unmount attempt. Workers should have released all handles.")
                    # Debug: check what's holding the mount
                    try:
                        lsof = subprocess.run(["lsof", "+c", "0", self.mount_path],
                                             capture_output=True, text=True, check=False, timeout=2)
                        if lsof.stdout:
                            log.debug(f"Open files on mount:\n{lsof.stdout}")
                    except Exception:
                        pass
                    return False
                log.debug(f"Unmounted {self.mount_path}")
                self.is_mounted = False
            except subprocess.TimeoutExpired:
                log.error(f"umount {self.mount_path} timed out")
                return False
            except Exception as e:
                log.warning(f"Failed to unmount {self.mount_path}: {e}")
                return False

        # Only clean up directories after successful unmount
        for dir_path in [self.upperdir, self.workdir, self.mount_path]:
            try:
                if os.path.exists(dir_path):
                    shutil.rmtree(dir_path)
            except Exception as e:
                log.warning(f"Failed to remove {dir_path}: {e}")

        # Clean up copied git metadata directory
        if self.copied_git_metadata_dir and os.path.exists(self.copied_git_metadata_dir):
            try:
                shutil.rmtree(self.copied_git_metadata_dir)
                log.debug(f"Cleaned up copied git metadata: {self.copied_git_metadata_dir}")
            except Exception as e:
                log.warning(f"Failed to remove copied git metadata {self.copied_git_metadata_dir}: {e}")

        return True

    def __enter__(self):
        """Mount overlayfs on context entry."""
        if not self.mount():
            raise RuntimeError(f"Failed to mount overlayfs at {self.mount_path}")
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Unmount and cleanup on context exit."""
        self.unmount()
        return False  # Don't suppress exceptions


def cleanup_stale_mounts():
    """Clean up any stale overlayfs mounts from previous runs."""
    try:
        # Check /proc/mounts for overlayfs mounts created by armbian-patch-worker
        with open('/proc/mounts', 'r') as f:
            mounts = f.read()

        for line in mounts.split('\n'):
            if 'armbian-patch-worker-' in line and 'overlay' in line:
                parts = line.split()
                if len(parts) >= 2:
                    mount_point = parts[1]
                    log.debug(f"Cleaning up stale mount: {mount_point}")
                    try:
                        subprocess.run(["umount", mount_point], capture_output=True, check=False)
                        # Try to remove the directory
                        if os.path.exists(mount_point):
                            shutil.rmtree(mount_point)
                    except Exception as e:
                        log.warning(f"Failed to cleanup stale mount {mount_point}: {e}")

        # Clean up any stale copied git metadata directories
        # These are in the git worktrees directory and end with -worker-{N}
        try:
            # Find all git worktrees directories
            git_worktrees_base = None
            if 'GIT_WORK_DIR' in os.environ:
                # Try to find the worktrees directory from the GIT_WORK_DIR
                git_work_dir = os.environ['GIT_WORK_DIR']
                # The worktrees metadata is in .git/worktrees/ of the bare repo
                # For kernel patches, this is typically in cache/git-bare/kernel/.git/worktrees/
                possible_worktrees = [
                    os.path.join(os.path.dirname(git_work_dir), '.git', 'worktrees'),
                    '/root/build/cache/git-bare/kernel/.git/worktrees',
                ]
                for possible in possible_worktrees:
                    if os.path.exists(possible):
                        git_worktrees_base = possible
                        break

            if git_worktrees_base and os.path.exists(git_worktrees_base):
                for dirname in os.listdir(git_worktrees_base):
                    # Match any directory ending with -worker-{number}
                    # Handles all worker IDs, not just 0-9
                    if '-worker-' in dirname:
                        # Verify it's a worker directory (ends with -worker-{digits})
                        import re as re_module
                        if re_module.search(r'-worker-\d+$', dirname):
                            worker_dir = os.path.join(git_worktrees_base, dirname)
                            log.debug(f"Cleaning up stale git metadata directory: {worker_dir}")
                            try:
                                shutil.rmtree(worker_dir)
                            except Exception as e:
                                log.warning(f"Failed to cleanup stale git metadata {worker_dir}: {e}")
        except Exception as e:
            log.debug(f"Could not clean up stale git metadata: {e}")

    except Exception as e:
        log.debug(f"Could not clean up stale mounts: {e}")


def get_available_memory_gb() -> float:
    """Get available memory in GB from /proc/meminfo."""
    try:
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.read()

        # Parse MemAvailable (or fallback to MemFree)
        for line in meminfo.split('\n'):
            if line.startswith('MemAvailable:'):
                return int(line.split()[1]) / 1024 / 1024  # Convert kB to GB
            if line.startswith('MemFree:'):
                mem_free = int(line.split()[1]) / 1024 / 1024
            if line.startswith('Buffers:'):
                buffers = int(line.split()[1]) / 1024 / 1024
            if line.startswith('Cached:'):
                cached = int(line.split()[1]) / 1024 / 1024

        # Fallback: estimate available as free + buffers + cached
        return mem_free + buffers + cached
    except Exception as e:
        log.warning(f"Failed to read memory info: {e}")
        return 8.0  # Conservative default


def get_total_memory_gb() -> float:
    """Get total memory in GB from /proc/meminfo."""
    try:
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.read()

        for line in meminfo.split('\n'):
            if line.startswith('MemTotal:'):
                return int(line.split()[1]) / 1024 / 1024  # Convert kB to GB
        return 8.0  # Default if not found
    except Exception as e:
        log.warning(f"Failed to read total memory: {e}")
        return 8.0


def get_memory_mb() -> float:
    """Get current process memory usage in MB from /proc/self/status."""
    try:
        with open('/proc/self/status', 'r') as f:
            for line in f:
                if line.startswith('VmRSS:'):
                    return int(line.split()[1]) / 1024  # Convert kB to MB
        return 0.0
    except Exception:
        return 0.0


def calculate_optimal_workers() -> int:
    """
    Calculate the optimal number of workers based on system resources.

    With overlayfs + git metadata copying, we've solved git contention entirely.
    We can now safely use all CPU cores without artificial limitations.

    Returns:
        Number of workers to use (all CPU cores by default)
    """
    # Get available memory in GB
    available_memory_gb = get_available_memory_gb()

    # Memory is not the bottleneck (<1MB per patch tested)
    # Very conservative estimate: 100MB per worker
    memory_based_workers = int(available_memory_gb * 1024 / 100)

    # Get CPU count
    cpu_count = os.cpu_count() or 1

    # I/O bound constraint: git + overlayfs don't scale beyond ~32 workers
    # Even with many CPU cores, filesystem operations become the bottleneck
    io_cap = 32

    # With overlayfs + git metadata copying, we have no git contention BETWEEN workers
    # But git operations themselves are I/O bound and don't scale infinitely
    workers = max(1, min(memory_based_workers, cpu_count, io_cap))

    log.info(f"System resources: {cpu_count} CPUs, {available_memory_gb:.2f} GB available memory")
    log.info(f"Calculated optimal workers: {workers} (capped at {io_cap} for I/O-bound git operations)")

    return workers


def parse_patch_stdout_for_files(stdout_output: str) -> List[str]:
    """
    Parse the stdout output of the patch command for the files actually patched.

    Args:
        stdout_output: The stdout output from the patch command

    Returns:
        List of files that were patched
    """
    # The patch command outputs lines like:
    # patching file drivers/gpu/drm/panfrost/panfrost_device.c
    regex = re.compile(r"^patching file\s+(.+)$")
    files = []
    for line in stdout_output.split('\n'):
        match = regex.match(line.strip())
        if match:
            file_path = match.group(1)
            # Remove any quoting that patch might have added
            file_path = file_path.strip('"').strip("'")
            files.append(file_path)
    return files


def rewrite_indexes_callback(x: re.Match) -> str:
    """
    Callback for rewriting git index lines in patches.

    This normalizes index lines to prevent meaningless SHA changes:
    - New files: index 000000000000..111111111111
    - Modified files: index 111111111111..222222222222
    """
    index_zero = f"{'0' * 12}"
    index_from_zero = f"index {'0' * 12}..{'1' * 12}"
    index_not_zero = f"index {'1' * 12}..{'2' * 12}"

    if x.group(1) == index_zero:
        return index_from_zero
    return index_not_zero


def apply_patch_date_to_files(patch_files: List[str], working_dir: str, patch_mtime: float, root_makefile_date: float) -> None:
    """
    Apply patch date to files that were patched.

    This ensures files modified by patches have proper mtimes.

    Args:
        patch_files: List of files that were patched
        working_dir: Working directory where files are located
        patch_mtime: Modification time from the patch file
        root_makefile_date: Modification time of root Makefile
    """
    # Use the maximum of patch mtime and root Makefile mtime
    final_mtime = max(patch_mtime, root_makefile_date)

    for file_name in patch_files:
        full_path = os.path.join(working_dir, file_name)
        if os.path.exists(full_path):
            # Only bump mtime, never lower it (issue #9028)
            current_mtime = os.path.getmtime(full_path)
            if final_mtime > current_mtime:
                os.utime(full_path, (final_mtime, final_mtime))


def export_commit_as_patch(working_dir: str, commit_hash: str, use_index_rewrite: bool = True) -> str:
    """
    Export a commit as a patch file using git format-patch.

    This performs the exact same operation as the serial implementation.

    Args:
        working_dir: Path to the working tree
        commit_hash: Hash of the commit to export
        use_index_rewrite: Whether to rewrite index lines

    Returns:
        The exported patch content as a string
    """
    cmd = [
        "git",
        "-C", working_dir,
        "format-patch",
        "--unified=3",
        "--keep-subject",
        "--no-encode-email-headers",
        "--signature", "Armbian",
        "--zero-commit",
        "--stat=120",
        "--stat-graph-width=10",
        "--abbrev=12",
        "-1",
        commit_hash,
        "--stdout"
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)

    patch_content = result.stdout

    # Rewrite index lines to normalize them
    if use_index_rewrite:
        index_rewrite_regexp = re.compile(r"index ([0-9a-f]{12})\.\.([0-9a-f]{12})")
        patch_content = index_rewrite_regexp.sub(rewrite_indexes_callback, patch_content)

    return patch_content


def _process_worker_patches_sequential(worker_items: List[PatchWorkItem], progress_queue=None) -> List[ParallelPatchResult]:
    """
    Process all patches assigned to a single worker sequentially.

    This is a module-level function designed to be picklable for ProcessPoolExecutor.

    IMPORTANT: Patches are processed sequentially WITHOUT resetting to base revision
    between patches WITHIN THE SAME GROUP. When the group changes, we reset to base.

    This ensures: 1) Cumulative changes within dependency groups are preserved
                   2) Independent groups start from a clean state

    NOTE: If a patch fails, we CONTINUE processing remaining patches.
    This allows independent patches in the same worker to succeed even if
    an earlier patch failed (they might not actually depend on each other).

    Args:
        worker_items: List of PatchWorkItem objects to process sequentially
        progress_queue: Optional multiprocessing queue for real-time progress updates

    Returns:
        List of ParallelPatchResult objects
    """
    worker_results = []
    previous_group_id = None
    for i, work_item in enumerate(worker_items):
        # CRITICAL: Detect group transitions - reset to base when group changes
        # First patch OR new group = reset to base revision
        if previous_group_id is None or work_item.group_id != previous_group_id:
            work_item.is_first_in_sequence = True
            previous_group_id = work_item.group_id
        else:
            work_item.is_first_in_sequence = False
        try:
            result = process_single_patch_worker(work_item)
            worker_results.append(result)

            # Report progress immediately if queue is available
            if progress_queue is not None:
                progress_queue.put(('progress', result))

        except Exception as e:
            log.error(f"Exception processing {work_item.patch_id}: {e}")
            error_result = ParallelPatchResult(
                patch_index=work_item.patch_index,
                patch_id=work_item.patch_id,
                success=False,
                error_message=str(e)
            )
            worker_results.append(error_result)

            # Report errors immediately too
            if progress_queue is not None:
                progress_queue.put(('progress', error_result))

    return worker_results


def process_single_patch_worker(item: PatchWorkItem) -> ParallelPatchResult:
    """
    Process a single patch in complete isolation using an overlayfs mount.

    This function performs ALL the same steps as the serial implementation:
    1. Reset git tree to base revision
    2. Create branch for this patch
    3. Parse patch with unidiff (already done in patch_data)
    4. Git archeology (skipped - data already in patch_data)
    5. Apply patch
    6. Apply patch dates
    7. Commit to git
    8. Export as patch

    This is designed to run in a separate thread with its own overlayfs mount.

    Args:
        item: PatchWorkItem containing all necessary patch information

    Returns:
        ParallelPatchResult with processing outcome
    """
    start_memory = get_memory_mb()
    # Start with original problems from parsing, append worker findings
    problems = item.patch_data.get('original_problems', [])
    patch_output = ""

    try:
        # Extract patch data
        patch_id = item.patch_data['patch_id']
        diff = item.patch_data['diff']
        diff_bytes = item.patch_data.get('diff_bytes')
        subject = item.patch_data.get('subject')
        from_name = item.patch_data.get('from_name', 'Unknown')
        from_email = item.patch_data.get('from_email', 'unknown@armbian.com')
        date_str = item.patch_data.get('date')
        desc = item.patch_data.get('desc', '')
        created_file_names = item.patch_data.get('created_file_names', [])
        deleted_file_names = item.patch_data.get('deleted_file_names', [])
        all_file_names_touched = item.patch_data.get('all_file_names_touched', [])
        renamed_file_names_source = item.patch_data.get('renamed_file_names_source', [])
        failed_to_parse = item.patch_data.get('failed_to_parse', False)
        is_autogen_dir = item.patch_data.get('is_autogen_dir', False)
        parent_relative_path = item.patch_data.get('parent_relative_path', '')
        counter = item.patch_data.get('counter', 0)
        patch_mtime = item.patch_data.get('patch_mtime', time.time())
        set_patch_date = item.patch_data.get('set_patch_date', True)
        allow_recreate_existing_files = item.patch_data.get('allow_recreate_existing_files', True)
        root_makefile_date = item.patch_data.get('root_makefile_date', 0)
        rewrite_patches = item.patch_data.get('rewrite_patches', False)
        split_patches = item.patch_data.get('split_patches', False)
        do_not_commit_files = item.patch_data.get('do_not_commit_files', [])
        do_not_commit_regexes = item.patch_data.get('do_not_commit_regexes', [])
        add_rebase_tags = item.patch_data.get('add_rebase_tags', True)

        # Extract diffstats and files for progress display
        diffstats = item.patch_data.get('diffstats', '')
        files = item.patch_data.get('files', '')

        # Initialize commit_messages list for tracking progress
        commit_messages = []

        log.debug(f"[Worker {item.mount_path}] Processing patch {item.patch_index}: {patch_id}")

        # STEP 1: Configure git safe.directory and reset git tree
        # ONLY reset if this is the first patch in the sequence
        # Subsequent patches build on the cumulative changes
        try:
            # Add mount path to git safe.directory to handle /tmp directories
            subprocess.run(
                ["git", "config", "--global", "--add", "safe.directory", item.mount_path],
                capture_output=True, check=False, timeout=10
            )

            repo = git.Repo(item.mount_path, odbt=git.GitCmdObjectDB)

            if item.is_first_in_sequence:
                # Hard reset to base revision - only for first patch in each dependency group
                # Base tree is pre-cleaned, so git clean is lighter (skip ignored files)
                repo.git.reset('--hard', item.base_revision)
                repo.git.clean('-fd')  # Skip -x (ignored files) since base is already clean

                # Create persistent worker branch (will be used for all patches in this worker)
                # Force=True in case branch already exists from previous group
                repo.create_head(item.worker_branch_name, item.base_revision, force=True)
                repo.heads[item.worker_branch_name].checkout()
                log.debug(f"[PATCH {item.patch_index}] Reset git tree to {item.base_revision} and checked out worker branch {item.worker_branch_name} (group {item.group_id})")
            else:
                # Not first patch in group - build on cumulative changes from previous patches in SAME group
                # Worker branch already exists and is checked out from previous patch in this group
                current_head = repo.head.commit.hexsha[:8]
                log.debug(f"[PATCH {item.patch_index}] Building on cumulative changes for patch {patch_id} (worker branch: {item.worker_branch_name}, group {item.group_id}, current HEAD: {current_head})")

                # Ensure we're on the worker branch
                if repo.active_branch.name != item.worker_branch_name:
                    repo.heads[item.worker_branch_name].checkout()

        except Exception as git_error:
            log.error(f"Failed to reset git tree for {patch_id}: {git_error}")
            return ParallelPatchResult(
                patch_index=item.patch_index,
                patch_id=patch_id,
                success=False,
                problems=problems,
                patch_output=patch_output,
                error_message=f"Git reset failed: {str(git_error)}"
            )

        # STEP 2: Sanity check for file overwrites (same as serial)
        for would_be_created_file in created_file_names:
            full_path = os.path.join(item.mount_path, would_be_created_file)
            if os.path.exists(full_path):
                problems.append("overwrites")
                if allow_recreate_existing_files:
                    log.debug(f"Tolerating recreation of {would_be_created_file} in {patch_id}")
                    os.remove(full_path)
                else:
                    log.warning(f"File {would_be_created_file} already exists, but patch {patch_id} would re-create it.")

        # STEP 3: Apply patch using the 'patch' utility (same as serial)
        if diff_bytes is None:
            real_input = diff.encode("utf-8")
        else:
            real_input = diff_bytes

        rejects_file = tempfile.mktemp()

        proc = subprocess.run(
            ["patch", "--batch", "-p1", "-N", f"--reject-file={rejects_file}", "--quoting-style=c"],
            cwd=item.mount_path,
            input=real_input,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False
        )

        stdout_output = proc.stdout.decode("utf-8").strip()
        stderr_output = proc.stderr.decode("utf-8").strip()
        patch_output = f"{stdout_output}\n" if stdout_output != "" else ""
        patch_output += f"{stderr_output}\n" if stderr_output != "" else ""

        # Check for rejects
        if os.path.exists(rejects_file):
            with open(rejects_file, "r") as f:
                rejects = f.read()
                if rejects:
                    patch_output += f"Rejects:\n{rejects}\n"
            os.remove(rejects_file)

        # Check for problems
        if " (offset" in stdout_output or " with fuzz " in stdout_output:
            log.debug(f"Patch {patch_id} needs rebase: offset/fuzz used during apply.")
            problems.append("needs_rebase")

        if "can't find file to patch at input line" in stdout_output:
            log.warning(f"Patch {patch_id} needs fixing: can't find file to patch.")
            problems.append("missing_file")

        # STEP 4: Parse patched files and apply dates (same as serial)
        actually_patched_files = []
        if set_patch_date:
            actually_patched_files = parse_patch_stdout_for_files(stdout_output)
            if actually_patched_files:
                apply_patch_date_to_files(actually_patched_files, item.mount_path, patch_mtime, root_makefile_date)

        # Check if patch failed to apply
        if proc.returncode != 0:
            problems.append("failed_apply")
            return ParallelPatchResult(
                patch_index=item.patch_index,
                patch_id=patch_id,
                success=False,
                problems=problems,
                patch_output=patch_output,
                error_message=f"Failed to apply patch (exit code {proc.returncode})"
            )

        # STEP 5: Commit changes to git (same as serial)
        try:
            # Add files to git staging area
            add_all_changes_in_git = False
            if (not failed_to_parse) and (not is_autogen_dir):
                all_files_to_add = []

                for file_name in all_file_names_touched:
                    is_delete = file_name in deleted_file_names

                    full_path = os.path.join(repo.working_tree_dir, file_name)
                    if (not os.path.exists(full_path)) and (not is_delete):
                        problems.append("wrong_strip_level")
                        log.error(f"File '{full_path}' does not exist, but is touched by {patch_id}")
                        add_all_changes_in_git = True
                    else:
                        all_files_to_add.append(file_name)

                # Add renamed source files
                for file_name in renamed_file_names_source:
                    if file_name.startswith("/"):
                        log.warning(f"File {file_name} claims to be a renamed source file, but is outside the repo.")
                        continue
                    all_files_to_add.append(file_name)

                if split_patches:
                    # Handle split patches (grouped by directory)
                    # For simplicity in parallel mode, we'll just add all files
                    add_all_changes_in_git = True
                elif not add_all_changes_in_git:
                    # Filter out files that should not be committed
                    final_files_to_add = [f for f in all_files_to_add if f not in do_not_commit_files]
                    final_files_to_add = [f for f in final_files_to_add if not any(re.match(r, f) for r in do_not_commit_regexes)]

                    if len(final_files_to_add) == 0:
                        log.warning(f"There are 0 files to commit post-config for {patch_id}")
                        problems.append("no_files_to_commit_after_config")
                        return ParallelPatchResult(
                            patch_index=item.patch_index,
                            patch_id=patch_id,
                            success=True,
                            commit_hash=None,
                            problems=problems,
                            patch_output=patch_output
                        )

                    repo.git.add("-f", final_files_to_add)

            if failed_to_parse or is_autogen_dir or add_all_changes_in_git:
                log.warning(f"Rescue: adding all changed files to git for {patch_id}")
                repo.git.add(repo.working_tree_dir)

            # Create commit message
            desc_no_none = desc if desc is not None else ""
            commit_message = f"{subject}\n\n{desc_no_none}"

            if add_rebase_tags:
                patch_id_str = f"{parent_relative_path}(:{counter})"
                commit_message = f"{patch_id_str}\n\nOriginal-Subject: {subject}\n{desc}"
                # Add problem tags
                if problems:
                    commit_message += f"\n\nProblems: {', '.join(problems)}"

            # Track commit details for progress display (matching serial format)
            commit_messages.append(f"Committing changes to git: {patch_id_str if add_rebase_tags else patch_id}")

            # Track files being added (for new files)
            for file_name in all_file_names_touched:
                if file_name in created_file_names:
                    commit_messages.append(f"Adding file {file_name} to git")

            # Create commit with proper author and date
            author = git.Actor(from_name, from_email)
            committer = git.Actor("Armbian AutoPatcher", "patching@armbian.com")

            # Retry logic for transient git race conditions (alternates sharing)
            # Error: [Errno 2] on temp object files = concurrent git writes
            max_retries = 3
            commit = None
            for attempt in range(max_retries):
                try:
                    commit = repo.index.commit(
                        message=commit_message,
                        author=author,
                        committer=committer,
                        author_date=date_str,
                        commit_date=date_str,
                        skip_hooks=True
                    )
                    break  # Success
                except FileNotFoundError as e:
                    if attempt < max_retries - 1:
                        log.warning(f"Git commit race condition on {patch_id} (attempt {attempt + 1}/{max_retries}): {e}")
                        time.sleep(0.1 * (2 ** attempt))  # Exponential backoff: 100ms, 200ms, 400ms
                    else:
                        raise  # Re-raise after final attempt

            commit_hash = commit.hexsha

            # Track successful commit
            commit_messages.append(f"Committed changes to git: {commit_hash}")

            # Check for empty commit
            if commit.stats.total["files"] == 0:
                problems.append("empty_commit")
                return ParallelPatchResult(
                    patch_index=item.patch_index,
                    patch_id=patch_id,
                    success=False,
                    problems=problems,
                    patch_output=patch_output,
                    error_message="Commit ended up empty"
                )

            log.debug(f"Committed changes for {patch_id}: {commit_hash}")

        except Exception as commit_error:
            log.error(f"Failed to commit changes for {patch_id}: {commit_error}")
            return ParallelPatchResult(
                patch_index=item.patch_index,
                patch_id=patch_id,
                success=False,
                problems=problems,
                patch_output=patch_output,
                error_message=f"Commit failed: {str(commit_error)}"
            )

        # STEP 6: Export commit as patch (same as serial)
        rewritten_patch = None
        if rewrite_patches and not is_autogen_dir and commit_hash:
            try:
                log.debug(f"About to export commit {commit_hash} for patch {patch_id} (patch_index={item.patch_index})")
                rewritten_patch = export_commit_as_patch(item.mount_path, commit_hash)
                # Log first few characters of the exported patch for debugging
                preview = rewritten_patch[:200] if rewritten_patch else "None"
                log.debug(f"Exported commit {commit_hash} as normalized patch for {patch_id}. Preview: {preview}")
            except Exception as export_error:
                # When rewriting patches, export failure is critical - re-raise to fail the operation
                # This matches serial behavior where export exceptions propagate
                log.error(f"Failed to export commit as patch for {patch_id}: {export_error}")
                raise

        end_memory = get_memory_mb()

        return ParallelPatchResult(
            patch_index=item.patch_index,
            patch_id=patch_id,
            success=True,
            commit_hash=commit_hash,
            rewritten_patch=rewritten_patch,
            problems=problems,
            patch_output=patch_output,
            memory_mb=end_memory - start_memory,
            diffstats=diffstats,
            files=files,
            commit_messages=commit_messages
        )

    except Exception as e:
        log.error(f"Exception processing patch {item.patch_id}: {e}")
        return ParallelPatchResult(
            patch_index=item.patch_index,
            patch_id=item.patch_id,
            success=False,
            problems=problems,
            patch_output=patch_output,
            error_message=str(e)
        )


def prepare_patch_data(patch_obj, root_makefile_date: float, apply_options: dict, pconfig: PatchingConfig) -> Dict[str, Any]:
    """
    Serialize a PatchInPatchFile object for parallel processing.

    This extracts all necessary data from the patch object to be processed in parallel.

    Args:
        patch_obj: The PatchInPatchFile object
        root_makefile_date: Modification time of root Makefile
        apply_options: Options from the apply configuration
        pconfig: Patching configuration

    Returns:
        Dictionary with all patch data for parallel processing
    """
    # Get patch file mtime
    patch_mtime = os.path.getmtime(patch_obj.parent.full_file_path())

    # Extract all necessary data from the patch object
    patch_data = {
        'patch_id': f"{patch_obj.parent.relative_dirs_and_base_file_name}(:{patch_obj.counter})",
        'diff': patch_obj.diff,
        'diff_bytes': getattr(patch_obj, 'diff_bytes', None),
        'subject': patch_obj.subject,
        'from_name': patch_obj.from_name,
        'from_email': patch_obj.from_email,
        'date': patch_obj.date,
        'desc': patch_obj.desc,
        'created_file_names': list(patch_obj.created_file_names) if patch_obj.created_file_names else [],
        'deleted_file_names': list(patch_obj.deleted_file_names) if patch_obj.deleted_file_names else [],
        'all_file_names_touched': list(patch_obj.all_file_names_touched) if patch_obj.all_file_names_touched else [],
        'renamed_file_names_source': list(patch_obj.renamed_file_names_source) if patch_obj.renamed_file_names_source else [],
        'failed_to_parse': patch_obj.failed_to_parse,
        'is_autogen_dir': patch_obj.parent.patch_dir.is_autogen_dir,
        'parent_relative_path': patch_obj.parent.relative_dirs_and_base_file_name,
        'counter': patch_obj.counter,
        'patch_file_path': patch_obj.parent.full_file_path(),
        'patch_mtime': patch_mtime,
        'set_patch_date': apply_options.get('set_patch_date', True),
        'allow_recreate_existing_files': apply_options.get('allow_recreate_existing_files', True),
        'root_makefile_date': root_makefile_date,
        'rewrite_patches': apply_options.get('rewrite_patches', False),
        'split_patches': apply_options.get('split_patches', False),
        'do_not_commit_files': pconfig.patches_to_git_config.do_not_commit_files if pconfig else [],
        'do_not_commit_regexes': pconfig.patches_to_git_config.do_not_commit_regexes if pconfig else [],
        'add_rebase_tags': apply_options.get('add_rebase_tags', True),
        'original_problems': list(patch_obj.problems),
        'diffstats': getattr(patch_obj, 'one_line_patch_stats', lambda: '')() if not patch_obj.failed_to_parse else '',
        'files': ', '.join(list(patch_obj.patched_file_stats_dict.keys())[:3]) if hasattr(patch_obj, 'patched_file_stats_dict') and patch_obj.patched_file_stats_dict else '',
    }

    return patch_data


def group_patches_by_series(patches: List, LINUXFAMILY: str) -> List[List]:
    """
    Group patches for parallel processing based on dependencies.

    Uses file-based dependency detection for all cases.
    Patches that share files MUST be processed sequentially in the same worker.

    Args:
        patches: List of PatchInPatchFile objects
        LINUXFAMILY: The kernel family name (unused, kept for API compatibility)

    Returns:
        List of patch groups, where each group must be processed sequentially
    """
    # Use file-based dependency detection for all cases
    log.info("Using file-based dependency detection...")
    return group_patches_by_implicit_dependencies(patches)


def group_patches_by_implicit_dependencies(patches: List) -> List[List]:
    """
    Detect implicit patch dependencies based on file overlap.

    Binary decision: If patches share ANY file, they MUST be sequential.
    If patches share NO files, they can be parallel.

    This uses union-find to group ALL transitively connected patches:
    - A shares file with B → same group
    - B shares file with C → same group
    - Therefore: A, B, C all in same group (transitive dependency)

    Args:
        patches: List of PatchInPatchFile objects

    Returns:
        List of patch groups where each group must be processed sequentially
        Groups can be processed in parallel
    """
    if not patches:
        return []

    # Step 1: Build file -> patches mapping
    file_to_patches = {}  # file_path -> list of patch indices
    unknown_file_patches = []  # Patches with failed_to_parse or autogen (no file info)

    for patch_idx, patch in enumerate(patches):
        # Track patches with unknown files (failed_to_parse or autogen)
        # These patches cannot be safely parallelized since we don't know what they touch
        if getattr(patch, 'failed_to_parse', False) or getattr(patch.parent.patch_dir, 'is_autogen_dir', False):
            unknown_file_patches.append(patch_idx)
            log.debug(f"Patch {patch_idx} ({patch.parent.relative_dirs_and_base_file_name}) has unknown files")
            continue

        # Include all_file_names_touched (new names after rename)
        for file_path in patch.all_file_names_touched:
            if file_path not in file_to_patches:
                file_to_patches[file_path] = []
            file_to_patches[file_path].append(patch_idx)

        # Include renamed_file_names_source (old names before rename)
        # Critical: patches modifying the old name must depend on this rename
        for file_path in patch.renamed_file_names_source:
            if file_path not in file_to_patches:
                file_to_patches[file_path] = []
            file_to_patches[file_path].append(patch_idx)

    log.info(f"File-based dependency: {len(patches)} patches touch {len(file_to_patches)} unique files")

    # Step 2: Build dependency graph using union-find
    # Patches that share ANY file are connected and must be sequential
    parent = list(range(len(patches)))

    def find(x):
        """Find root of component with path compression."""
        if parent[x] != x:
            parent[x] = find(parent[x])
        return parent[x]

    def union(x, y):
        """Merge two components."""
        root_x = find(x)
        root_y = find(y)
        if root_x != root_y:
            parent[root_y] = root_x

    # For each file, union all patches that touch it
    connections = 0
    for file_path, patch_indices in file_to_patches.items():
        if len(patch_indices) > 1:
            # These patches share a file - they MUST be sequential
            first_patch = patch_indices[0]
            for other_patch in patch_indices[1:]:
                union(first_patch, other_patch)
                connections += 1

    log.info(f"File-based dependency: Found {connections} file-sharing connections")

    # Handle unknown-file patches conservatively
    # These patches (failed_to_parse or autogen) have no file information
    # They MUST be serialized with each other to avoid potential conflicts
    if unknown_file_patches:
        log.info(f"File-based dependency: {len(unknown_file_patches)} patches with unknown files (serializing)")
        # Union all unknown-file patches together into a single sequential chain
        for i in range(len(unknown_file_patches) - 1):
            union(unknown_file_patches[i], unknown_file_patches[i + 1])
            connections += 1

    # Step 3: Group patches by their component root
    groups_dict = {}  # root -> list of patches
    for patch_idx in range(len(patches)):
        root = find(patch_idx)
        if root not in groups_dict:
            groups_dict[root] = []
        groups_dict[root].append(patches[patch_idx])

    groups = list(groups_dict.values())

    # Step 4: Sort each group to preserve original order
    for group in groups:
        group.sort(key=lambda p: patches.index(p))

    # Log grouping results
    total_patches = len(patches)
    total_groups = len(groups)

    # DEBUG: Log group composition to verify grouping is working
    log.debug("File-based dependency: Sample group composition:")
    for i, group in enumerate(groups[:5]):  # Log first 5 groups
        patch_names = [f"{p.parent.relative_dirs_and_base_file_name}(:{p.counter})" for p in group]
        log.debug(f"  Group {i} ({len(group)} patches): {', '.join(patch_names[:3])}{'...' if len(patch_names) > 3 else ''}")
    independent_groups = sum(1 for g in groups if len(g) == 1)
    chained_groups = total_groups - independent_groups

    log.info(f"File-based dependency: {total_patches} patches → {total_groups} groups")
    log.info(f"  - {independent_groups} independent (parallel)")
    log.info(f"  - {chained_groups} chains (sequential)")

    if chained_groups > 0:
        chain_sizes = sorted([len(g) for g in groups if len(g) > 1], reverse=True)[:5]
        log.info(f"  - Largest chains: {chain_sizes}")

    return groups


def process_patches_parallel(
    patches: List,
    git_work_dir: str,
    base_revision: str,
    num_workers: int,
    root_makefile_date: float,
    apply_options: dict,
    pconfig: PatchingConfig,
    LINUXFAMILY: str = "",
    progress_callback=None
) -> List[ParallelPatchResult]:
    """
    Process patches in parallel using overlayfs mounts.

    This is the main entry point for parallel patch processing.

    Args:
        patches: List of PatchInPatchFile objects
        git_work_dir: Base git repository directory (lowerdir for overlayfs)
        base_revision: Git revision to use as base
        num_workers: Number of parallel workers (0 = auto-calculate)
        root_makefile_date: Modification time of root Makefile
        apply_options: Options for patch application
        pconfig: Patching configuration
        LINUXFAMILY: Kernel family name (for series handling)
        progress_callback: Optional callback for progress updates

    Returns:
        List of ParallelPatchResult objects
    """
    results = []
    mounts = []

    try:
        # Clean up any stale mounts first
        log.debug("Cleaning up any stale overlayfs mounts...")
        cleanup_stale_mounts()

        # IMPORTANT: Clean base git tree ONCE before creating mounts
        # This prevents N workers from each doing expensive git clean traversals
        # Overlayfs mounts inherit this clean state via lowerdir
        log.debug(f"Cleaning base git tree at {git_work_dir} (single traversal)...")
        try:
            base_repo = git.Repo(git_work_dir, odbt=git.GitCmdObjectDB)
            base_repo.git.reset('--hard', base_revision)
            base_repo.git.clean('-fdx')
            log.debug("Base git tree cleaned successfully")
        except Exception as e:
            log.error(f"Failed to clean base git tree: {e}")
            return results

        # Calculate optimal workers if not specified
        if num_workers == 0:
            num_workers = calculate_optimal_workers()

        # Group patches based on dependencies
        log.debug(f"Grouping {len(patches)} patches for parallel processing...")
        patch_groups = group_patches_by_series(patches, LINUXFAMILY)
        group_info = f"{len(patch_groups)} groups"
        if len(patch_groups) == len(patches):
            group_info += " (all independent)"
        log.debug(f"Created {group_info} for parallel processing")

        # Cap workers at number of groups - no point in more workers than groups
        if num_workers > len(patch_groups):
            log.debug(f"Capping workers from {num_workers} to {len(patch_groups)} (number of groups)")
            num_workers = len(patch_groups)

        # Create overlayfs mounts for parallel workers
        temp_base = tempfile.mkdtemp(prefix="armbian-patch-parallel-")
        log.debug(f"Creating {num_workers} overlayfs mounts in {temp_base}")

        for i in range(num_workers):
            mount_path = os.path.join(temp_base, f"worker-{i}")

            # Create overlayfs mount
            # The mount will fix .git file paths automatically
            overlay = OverlayFSMount(git_work_dir, mount_path, i)
            if overlay.mount():
                mounts.append(overlay)
                log.debug(f"Created overlayfs mount {i}: {mount_path}")
            else:
                log.warning(f"Failed to create overlayfs mount {i}")

        # If we couldn't create any mounts, fail
        if not mounts:
            log.error("No overlayfs mounts were created successfully")
            return results

        # Adjust worker count to actual mounts created
        actual_workers = len(mounts)
        log.debug(f"Using {actual_workers} workers")

        # Prepare work items for all patches
        # Assign entire groups to workers (not individual patches)
        # This preserves sequential dependencies within groups
        worktree_patch_groups = [[] for _ in range(actual_workers)]
        total_patches = 0
        timestamp = int(time.time())

        # Create worker-level branch names once per worker (not per group!)
        # All patches assigned to a worker will use the same branch for sequential processing
        worker_branch_names = [f"patch-worker-{worker_id}-{timestamp}" for worker_id in range(actual_workers)]

        # Assign entire groups to workers using round-robin
        # Each worker processes all patches in its assigned groups sequentially
        for group_idx, group in enumerate(patch_groups):
            # Assign entire group to one worker using round-robin
            worker_id = group_idx % actual_workers
            mount = mounts[worker_id]

            for patch in group:
                total_patches += 1
                patch_data = prepare_patch_data(patch, root_makefile_date, apply_options, pconfig)

                # CRITICAL: Use the ORIGINAL patch position in the input list as patch_index
                # This ensures correct mapping when results are returned, regardless of grouping/reordering
                original_patch_index = patches.index(patch)

                work_item = PatchWorkItem(
                    patch_index=original_patch_index,
                    patch_id=f"{patch.parent.relative_dirs_and_base_file_name}(:{patch.counter})",
                    patch_data=patch_data,
                    mount_path=mount.mount_path,
                    base_revision=base_revision,
                    worker_branch_name=worker_branch_names[worker_id],  # Shared across ALL patches in this worker
                    group_id=group_idx  # Track which group this patch belongs to (for reset detection)
                )
                worktree_patch_groups[worker_id].append(work_item)

        log.debug(f"Starting parallel processing with {actual_workers} workers...")
        log.debug("Each worker processes its assigned patches sequentially")
        start_time = time.time()

        # Process each worker's patches in parallel using processes (not threads)
        # Processes bypass Python's GIL for true CPU parallelism
        completed_count = 0

        # Use Manager Queue for progress updates to enable real-time feedback
        manager = Manager()
        progress_queue = manager.Queue() if progress_callback else None

        with ProcessPoolExecutor(max_workers=actual_workers) as executor:
            # Submit each worker's patch group to be processed sequentially
            future_to_worker = {}
            for worker_id, worker_items in enumerate(worktree_patch_groups):
                if worker_items:  # Only submit if there are patches to process
                    future = executor.submit(_process_worker_patches_sequential, worker_items, progress_queue)
                    future_to_worker[future] = worker_id

            # Monitor progress queue for real-time updates while workers run
            # This gives immediate feedback instead of waiting for batch completion
            pending_futures = set(future_to_worker.keys())
            reported_indices = set()  # Track which patches we've already reported

            while pending_futures:
                # Process all available progress updates first (non-blocking)
                if progress_queue:
                    while not progress_queue.empty():
                        try:
                            item = progress_queue.get_nowait()
                            if item[0] == 'progress':
                                result = item[1]
                                if result.patch_index not in reported_indices:
                                    reported_indices.add(result.patch_index)
                                    completed_count += 1
                                    progress_callback(completed_count, total_patches, result)
                        except:
                            break  # Queue empty, exit loop

                # Check for completed futures (workers that finished)
                done_futures = [f for f in pending_futures if f.done()]
                for future in done_futures:
                    worker_id = future_to_worker[future]
                    pending_futures.remove(future)
                    try:
                        worker_results = future.result()
                        results.extend(worker_results)

                        # Report any remaining results from this worker that weren't reported via queue
                        for result in worker_results:
                            if result.patch_index not in reported_indices:
                                reported_indices.add(result.patch_index)
                                completed_count += 1
                                if progress_callback:
                                    progress_callback(completed_count, total_patches, result)

                        log.debug(f"Worker {worker_id} completed {len(worker_results)} patches")
                    except Exception as e:
                        log.error(f"Exception in worker {worker_id}: {e}")

                # Small sleep to avoid busy-waiting if nothing to do
                if not done_futures and (not progress_queue or progress_queue.empty()):
                    time.sleep(0.05)

        # Sort results by patch index for consistent output
        results.sort(key=lambda r: r.patch_index)

        elapsed = time.time() - start_time
        successful = [r for r in results if r.success]
        failed = [r for r in results if not r.success]

        log.info(f"Completed {total_patches} patches in {elapsed:.1f} seconds ({total_patches/elapsed:.2f} patches/sec)")
        log.info(f"Successful: {len(successful)}, Failed: {len(failed)}")

        # Memory statistics
        mem_results = [r for r in results if r.memory_mb is not None]
        if mem_results:
            avg_mem = sum(r.memory_mb for r in mem_results) / len(mem_results)
            max_mem = max(r.memory_mb for r in mem_results)
            log.debug(f"Avg memory per patch: {avg_mem:.1f} MB, Max: {max_mem:.1f} MB")

    finally:
        # Clean up overlayfs mounts
        log.debug("Cleaning up overlayfs mounts...")
        for overlay in mounts:
            overlay.unmount()

        # Clean up manager
        if 'manager' in locals():
            manager.shutdown()

        # Remove temp directory
        try:
            if 'temp_base' in locals():
                shutil.rmtree(temp_base)
        except Exception as e:
            log.warning(f"Failed to remove temp directory {temp_base}: {e}")

    return results


def update_patches_from_parallel_results(
    patches: List,
    parallel_results: List[ParallelPatchResult],
    apply_options: dict,
    git_repo,
    pconfig: PatchingConfig
) -> None:
    """
    Update the original patch objects with results from parallel processing.

    This updates the patch objects in place so they reflect the results of
    parallel processing, maintaining compatibility with the rest of the framework.

    CRITICAL: Uses patch_index for safe lookup, not position-based zip().
    This ensures correct mapping even if patches are grouped/reordered.

    Args:
        patches: List of PatchInPatchFile objects (updated in place)
        parallel_results: List of ParallelPatchResult from parallel processing
        apply_options: Options from apply configuration
        git_repo: Git repository object
        pconfig: Patching configuration
    """
    split_patches = apply_options.get('split_patches', False)
    rewrite_patches_in_place = apply_options.get('rewrite_patches', False)

    # Log for debugging: track patches vs results
    log.debug(f"update_patches_from_parallel_results: {len(patches)} patches, {len(parallel_results)} results")

    # Create a map of patch_index to result for safe lookup
    results_by_index = {result.patch_index: result for result in parallel_results}

    # Check for missing results
    missing_patches = set(range(len(patches))) - set(results_by_index.keys())
    if missing_patches:
        log.error(f"Missing results for {len(missing_patches)} patches: {sorted(missing_patches)}")

    # Update each patch by matching patch_index (not by position!)
    # This ensures all patches are updated even if some results are missing
    for patch_idx, patch_obj in enumerate(patches):
        result = results_by_index.get(patch_idx)

        if result is None:
            # No result for this patch - mark as failed
            log.warning(f"No result found for patch {patch_idx} ({patch_obj}), marking as failed")
            patch_obj.applied_ok = False
            continue

        # Update basic status
        patch_obj.applied_ok = result.success

        # Update problems
        patch_obj.problems = result.problems

        # Update patch output
        if hasattr(patch_obj, 'patch_output'):
            patch_obj.patch_output = result.patch_output

        # Update commit hash
        if result.commit_hash and not split_patches:
            patch_obj.git_commit_hash = result.commit_hash

        # Update rewritten patch
        if result.rewritten_patch and rewrite_patches_in_place and not patch_obj.parent.patch_dir.is_autogen_dir:
            patch_obj.rewritten_patch = result.rewritten_patch
