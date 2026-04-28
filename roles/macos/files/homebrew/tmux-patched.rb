# frozen_string_literal: true

# Patched tmux 3.6a — vanilla 3.6a release plus upstream commit 2a5715f
# (https://github.com/tmux/tmux/commit/2a5715f), which fixes a NULL pointer
# dereference in window_copy_pipe_run that crashes tmux during
# copy-pipe-and-cancel when job_run returns NULL.
#
# Rollback: when upstream Homebrew tmux ships a release containing the fix,
# `bin/provision` will fail on the upstream-version-guard task. At that
# point: `brew uninstall --formula tmux-patched`; remove this formula file;
# remove the corresponding install + version-guard tasks; `brew install tmux`.
class TmuxPatched < Formula
  desc "Terminal multiplexer (3.6a + window_copy_pipe_run NULL-deref fix)"
  homepage "https://tmux.github.io/"
  url "https://github.com/tmux/tmux/releases/download/3.6a/tmux-3.6a.tar.gz"
  sha256 "b6d8d9c76585db8ef5fa00d4931902fa4b8cbe8166f528f44fc403961a3f3759"
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
    assert_match "tmux 3.6a", shell_output("#{bin}/tmux -V")
  end
end
