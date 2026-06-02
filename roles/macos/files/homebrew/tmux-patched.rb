# frozen_string_literal: true

# Patched tmux 3.6b — vanilla 3.6b release plus upstream commit 2a5715f
# (https://github.com/tmux/tmux/commit/2a5715f), which fixes a NULL pointer
# dereference in window_copy_pipe_run that crashes tmux during
# copy-pipe-and-cancel when job_run returns NULL. As of tmux 3.6b that fix is
# still only on master — no tagged release contains it — so we keep applying it
# on top of the latest release.
#
# Rollback: the upstream-version-guard task in roles/macos/tasks/main.yml trips
# on ANY upstream version bump; it does NOT prove the fix has shipped. When it
# trips, re-check whether the new upstream release contains commit 2a5715f
# (https://github.com/tmux/tmux/commit/2a5715f). If it does, the workaround can
# be removed: `brew uninstall --formula tmux-patched`; delete this formula file;
# remove the install + version-guard tasks; `brew install tmux`. If it does NOT,
# rebase the patch onto the new release instead (update url/sha256/test/desc
# here, bump the pin in vars/tool_versions.yml, and bump the guard's expected
# version + task name in roles/macos/tasks/main.yml).
class TmuxPatched < Formula
  desc "Terminal multiplexer (3.6b + window_copy_pipe_run NULL-deref fix)"
  homepage "https://tmux.github.io/"
  url "https://github.com/tmux/tmux/releases/download/3.6b/tmux-3.6b.tar.gz"
  sha256 "390759d25fdba016887ec982b808927e637070fd7d03a8021f8ef3102b9ae3c7"
  license "ISC"

  depends_on "libevent"
  depends_on "ncurses"
  depends_on "utf8proc"

  conflicts_with "tmux", because: "both install bin/tmux"

  patch do
    url "https://github.com/tmux/tmux/commit/2a5715fad5a3f7c7cec5ba8a0a26b85a0df2c259.patch?full_index=1"
    sha256 "406045954873952fe7ba9d9510b26a81b9a17c9c81607f8db836396882644b5e"
  end

  def install
    system "./configure", *std_configure_args,
           "--sysconfdir=#{etc}",
           "--enable-utf8proc"
    system "make", "install"
  end

  test do
    assert_match "tmux 3.6b", shell_output("#{bin}/tmux -V")
  end
end
