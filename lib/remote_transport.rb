# frozen_string_literal: true

module RemoteTransport
  class CodespaceTransport
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def ssh_prefix
      "gh codespace ssh -c #{@name} --"
    end

    def workspace_type
      'Codespace'
    end
  end

  class DevpodTransport
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def ssh_prefix
      "ssh #{@name}.devpod"
    end

    def workspace_type
      'DevPod'
    end
  end
end
