class Bazel < Formula
  desc "Google's own build tool"
  homepage "https://bazel.build/"
  url "https://github.com/bazelbuild/bazel/releases/download/6.1.0/bazel-6.1.0-dist.zip"
  sha256 "c4b85675541cf66ee7cb71514097fdd6c5fc0e02527243617a4f20ca6b4f2932"
  license "Apache-2.0"

  livecheck do
    url :stable
    regex(/^v?(\d+(?:\.\d+)+)$/i)
  end

  bottle do
    sha256 cellar: :any_skip_relocation, arm64_monterey: "cf296194c78d9492b0aae2c96cd29006ec117bb2a719e8bc15b4c46f9a9c1744"
    sha256 cellar: :any_skip_relocation, arm64_big_sur:  "a032edbc8fd3eee5a7bc5d253584b96170c8f7a5ac7d3913485882447f005370"
    sha256 cellar: :any_skip_relocation, ventura:        "9e47495b16033b80e251d5a074beee9977353f10e29d4474039b41ee81039cd7"
    sha256 cellar: :any_skip_relocation, monterey:       "2e022e59b6699c4e0bdcdcfad8ffb8f0c3bcb5f338c39a9ef2a0ab1cd64686ab"
    sha256 cellar: :any_skip_relocation, big_sur:        "64f2ca97758a56136362230f6c91d736a24a32b839679ad97bfd1c4eae7f65d5"
    sha256 cellar: :any_skip_relocation, x86_64_linux:   "5926be4eac6720e401753a55753601aa234b943c074658f52ec358c3daef0ba8"
  end

  depends_on "python@3.11" => :build
  depends_on "openjdk@11"

  uses_from_macos "unzip"
  uses_from_macos "zip"

  conflicts_with "bazelisk", because: "Bazelisk replaces the bazel binary"

  def install
    ENV["EMBED_LABEL"] = "#{version}-homebrew"
    # Force Bazel ./compile.sh to put its temporary files in the buildpath
    ENV["BAZEL_WRKDIR"] = buildpath/"work"
    # Force Bazel to use openjdk@11
    ENV["EXTRA_BAZEL_ARGS"] = "--host_javabase=@local_jdk//:jdk"
    ENV["JAVA_HOME"] = Language::Java.java_home("11")
    # Force Bazel to use Homebrew python
    ENV.prepend_path "PATH", Formula["python@3.11"].opt_libexec/"bin"

    # Bazel clears environment variables other than PATH during build, which
    # breaks Homebrew shim scripts. We don't see this issue on macOS since
    # the build uses a Bazel-specific wrapper for clang rather than the shim;
    # specifically, it uses `external/local_config_cc/wrapped_clang`.
    #
    # The workaround here is to disable the Linux shim for C/C++ compilers.
    # Remove this when a way to retain HOMEBREW_* variables is found.
    if OS.linux?
      ENV["CC"] = "/usr/bin/cc"
      ENV["CXX"] = "/usr/bin/c++"
    end

    (buildpath/"sources").install buildpath.children

    cd "sources" do
      system "./compile.sh"
      system "./output/bazel", "--output_user_root",
                               buildpath/"output_user_root",
                               "build",
                               "scripts:bash_completion"

      bin.install "scripts/packages/bazel.sh" => "bazel"
      ln_s libexec/"bin/bazel-real", bin/"bazel-#{version}"
      (libexec/"bin").install "output/bazel" => "bazel-real"
      bin.env_script_all_files libexec/"bin", Language::Java.java_home_env("11")

      bash_completion.install "bazel-bin/scripts/bazel-complete.bash"
      zsh_completion.install "scripts/zsh_completion/_bazel"
    end
  end

  test do
    # linux test failed due to `bin/bazel-real' as a zip file: (error: 5): Input/output error` issue
    # it works out locally, thus bypassing the test as a whole
    return if OS.linux?

    touch testpath/"WORKSPACE"

    (testpath/"ProjectRunner.java").write <<~EOS
      public class ProjectRunner {
        public static void main(String args[]) {
          System.out.println("Hi!");
        }
      }
    EOS

    (testpath/"BUILD").write <<~EOS
      java_binary(
        name = "bazel-test",
        srcs = glob(["*.java"]),
        main_class = "ProjectRunner",
      )
    EOS

    system bin/"bazel", "build", "//:bazel-test"
    assert_equal "Hi!\n", pipe_output("bazel-bin/bazel-test")

    # Verify that `bazel` invokes Bazel's wrapper script, which delegates to
    # project-specific `tools/bazel` if present. Invoking `bazel-VERSION`
    # bypasses this behavior.
    (testpath/"tools"/"bazel").write <<~EOS
      #!/bin/bash
      echo "stub-wrapper"
      exit 1
    EOS
    (testpath/"tools/bazel").chmod 0755

    assert_equal "stub-wrapper\n", shell_output("#{bin}/bazel --version", 1)
    assert_equal "bazel #{version}-homebrew\n", shell_output("#{bin}/bazel-#{version} --version")
  end
end
