from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

from ansible.plugins.connection.ssh import Connection as SSHConnection

DOCUMENTATION = '''
    name: ssh
    short_description: connect via SSH client binary
    description:
        - This connection plugin allows Ansible to communicate to the target machines through normal SSH command line.
        - Ansible does not expose a channel to allow communication between the user and the SSH process to accept
          a password manually to decrypt an SSH key when using this connection plugin (which is the default). The
          use of C(ssh-agent) is highly recommended.
    author: ansible (@core)
    extends_documentation_fragment:
        - connection_pipelining
    version_added: historical
    notes:
        - Many options default to C(None) here but that only means we do not override the SSH tool's defaults and/or configuration.
          For example, if you specify the port in this plugin it will override any C(Port) entry in your C(.ssh/config).
        - The ssh CLI tool uses return code 255 as a 'connection error', this can conflict with commands/tools that
          also return 255 as an error code and will look like an 'unreachable' condition or 'connection error' to this plugin.
    options:
      host:
          description: Hostname/IP to connect to.
          default: inventory_hostname
          vars:
               - name: inventory_hostname
               - name: ansible_host
               - name: ansible_ssh_host
               - name: delegated_vars['ansible_host']
               - name: delegated_vars['ansible_ssh_host']
      host_key_checking:
          description: Determines if SSH should check host keys.
          default: True
          type: boolean
          ini:
              - section: defaults
                key: 'host_key_checking'
              - section: ssh_connection
                key: 'host_key_checking'
                version_added: '2.5'
          env:
              - name: ANSIBLE_HOST_KEY_CHECKING
              - name: ANSIBLE_SSH_HOST_KEY_CHECKING
                version_added: '2.5'
          vars:
              - name: ansible_host_key_checking
                version_added: '2.5'
              - name: ansible_ssh_host_key_checking
                version_added: '2.5'
      password:
          description: Authentication password for the C(remote_user). Can be supplied as CLI option.
          vars:
              - name: ansible_password
              - name: ansible_ssh_pass
              - name: ansible_ssh_password
      sshpass_prompt:
          description:
              - Password prompt that sshpass should search for. Supported by sshpass 1.06 and up.
              - Defaults to C(Enter PIN for) when pkcs11_provider is set.
          default: ''
          ini:
              - section: 'ssh_connection'
                key: 'sshpass_prompt'
          env:
              - name: ANSIBLE_SSHPASS_PROMPT
          vars:
              - name: ansible_sshpass_prompt
          version_added: '2.10'
      ssh_args:
          description: Arguments to pass to all SSH CLI tools.
          default: '-C -o ControlMaster=auto -o ControlPersist=60s'
          ini:
              - section: 'ssh_connection'
                key: 'ssh_args'
          env:
              - name: ANSIBLE_SSH_ARGS
          vars:
              - name: ansible_ssh_args
                version_added: '2.7'
      ssh_common_args:
          description: Common extra args for all SSH CLI tools.
          ini:
              - section: 'ssh_connection'
                key: 'ssh_common_args'
                version_added: '2.7'
          env:
              - name: ANSIBLE_SSH_COMMON_ARGS
                version_added: '2.7'
          vars:
              - name: ansible_ssh_common_args
          cli:
              - name: ssh_common_args
          default: ''
      ssh_executable:
          default: ssh
          description:
            - This defines the location of the SSH binary. It defaults to C(ssh) which will use the first SSH binary available in $PATH.
            - This option is usually not required, it might be useful when access to system SSH is restricted,
              or when using SSH wrappers to connect to remote hosts.
          env: [{name: ANSIBLE_SSH_EXECUTABLE}]
          ini:
          - {key: ssh_executable, section: ssh_connection}
          #const: ANSIBLE_SSH_EXECUTABLE
          version_added: "2.2"
          vars:
              - name: ansible_ssh_executable
                version_added: '2.7'
      sftp_executable:
          default: sftp
          description:
            - This defines the location of the sftp binary. It defaults to C(sftp) which will use the first binary available in $PATH.
          env: [{name: ANSIBLE_SFTP_EXECUTABLE}]
          ini:
          - {key: sftp_executable, section: ssh_connection}
          version_added: "2.6"
          vars:
              - name: ansible_sftp_executable
                version_added: '2.7'
      scp_executable:
          default: scp
          description:
            - This defines the location of the scp binary. It defaults to C(scp) which will use the first binary available in $PATH.
          env: [{name: ANSIBLE_SCP_EXECUTABLE}]
          ini:
          - {key: scp_executable, section: ssh_connection}
          version_added: "2.6"
          vars:
              - name: ansible_scp_executable
                version_added: '2.7'
      scp_extra_args:
          description: Extra exclusive to the C(scp) CLI
          vars:
              - name: ansible_scp_extra_args
          env:
            - name: ANSIBLE_SCP_EXTRA_ARGS
              version_added: '2.7'
          ini:
            - key: scp_extra_args
              section: ssh_connection
              version_added: '2.7'
          cli:
            - name: scp_extra_args
          default: ''
      sftp_extra_args:
          description: Extra exclusive to the C(sftp) CLI
          vars:
              - name: ansible_sftp_extra_args
          env:
            - name: ANSIBLE_SFTP_EXTRA_ARGS
              version_added: '2.7'
          ini:
            - key: sftp_extra_args
              section: ssh_connection
              version_added: '2.7'
          cli:
            - name: sftp_extra_args
          default: ''
      ssh_extra_args:
          description: Extra exclusive to the SSH CLI.
          vars:
              - name: ansible_ssh_extra_args
          env:
            - name: ANSIBLE_SSH_EXTRA_ARGS
              version_added: '2.7'
          ini:
            - key: ssh_extra_args
              section: ssh_connection
              version_added: '2.7'
          cli:
            - name: ssh_extra_args
          default: ''
      reconnection_retries:
          description:
            - Number of attempts to connect.
            - Ansible retries connections only if it gets an SSH error with a return code of 255.
            - Any errors with return codes other than 255 indicate an issue with program execution.
          default: 0
          type: integer
          env:
            - name: ANSIBLE_SSH_RETRIES
          ini:
            - section: connection
              key: retries
            - section: ssh_connection
              key: retries
          vars:
            - name: ansible_ssh_retries
              version_added: '2.7'
      port:
          description: Remote port to connect to.
          type: int
          ini:
            - section: defaults
              key: remote_port
          env:
            - name: ANSIBLE_REMOTE_PORT
          vars:
            - name: ansible_port
            - name: ansible_ssh_port
          keyword:
            - name: port
      remote_user:
          description:
              - User name with which to login to the remote server, normally set by the remote_user keyword.
              - If no user is supplied, Ansible will let the SSH client binary choose the user as it normally.
          ini:
            - section: defaults
              key: remote_user
          env:
            - name: ANSIBLE_REMOTE_USER
          vars:
            - name: ansible_user
            - name: ansible_ssh_user
          cli:
            - name: user
          keyword:
            - name: remote_user
      pipelining:
          env:
            - name: ANSIBLE_PIPELINING
            - name: ANSIBLE_SSH_PIPELINING
          ini:
            - section: defaults
              key: pipelining
            - section: connection
              key: pipelining
            - section: ssh_connection
              key: pipelining
          vars:
            - name: ansible_pipelining
            - name: ansible_ssh_pipelining
      private_key_file:
          description:
              - Path to private key file to use for authentication.
          ini:
            - section: defaults
              key: private_key_file
          env:
            - name: ANSIBLE_PRIVATE_KEY_FILE
          vars:
            - name: ansible_private_key_file
            - name: ansible_ssh_private_key_file
          cli:
            - name: private_key_file
              option: '--private-key'
      control_path:
        description:
          - This is the location to save SSH's ControlPath sockets, it uses SSH's variable substitution.
          - Since 2.3, if null (default), ansible will generate a unique hash. Use ``%(directory)s`` to indicate where to use the control dir path setting.
          - Before 2.3 it defaulted to ``control_path=%(directory)s/ansible-ssh-%%h-%%p-%%r``.
          - Be aware that this setting is ignored if C(-o ControlPath) is set in ssh args.
        env:
          - name: ANSIBLE_SSH_CONTROL_PATH
        ini:
          - key: control_path
            section: ssh_connection
        vars:
          - name: ansible_control_path
            version_added: '2.7'
      control_path_dir:
        default: ~/.ansible/cp
        description:
          - This sets the directory to use for ssh control path if the control path setting is null.
          - Also, provides the ``%(directory)s`` variable for the control path setting.
        env:
          - name: ANSIBLE_SSH_CONTROL_PATH_DIR
        ini:
          - section: ssh_connection
            key: control_path_dir
        vars:
          - name: ansible_control_path_dir
            version_added: '2.7'
      sftp_batch_mode:
        default: 'yes'
        description: 'TODO: write it'
        env: [{name: ANSIBLE_SFTP_BATCH_MODE}]
        ini:
        - {key: sftp_batch_mode, section: ssh_connection}
        type: bool
        vars:
          - name: ansible_sftp_batch_mode
            version_added: '2.7'
      ssh_transfer_method:
        description:
            - "Preferred method to use when transferring files over ssh"
            - Setting to 'smart' (default) will try them in order, until one succeeds or they all fail
            - For OpenSSH >=9.0 you must add an additional option to enable scp (scp_extra_args="-O")
            - Using 'piped' creates an ssh pipe with C(dd) on either side to copy the data
        choices: ['sftp', 'scp', 'piped', 'smart']
        env: [{name: ANSIBLE_SSH_TRANSFER_METHOD}]
        ini:
            - {key: transfer_method, section: ssh_connection}
        vars:
            - name: ansible_ssh_transfer_method
              version_added: '2.12'
      scp_if_ssh:
        deprecated:
              why: In favor of the "ssh_transfer_method" option.
              version: "2.17"
              alternatives: ssh_transfer_method
        default: smart
        description:
          - "Preferred method to use when transferring files over SSH."
          - When set to I(smart), Ansible will try them until one succeeds or they all fail.
          - If set to I(True), it will force 'scp', if I(False) it will use 'sftp'.
          - For OpenSSH >=9.0 you must add an additional option to enable scp (scp_extra_args="-O")
          - This setting will overridden by ssh_transfer_method if set.
        env: [{name: ANSIBLE_SCP_IF_SSH}]
        ini:
        - {key: scp_if_ssh, section: ssh_connection}
        vars:
          - name: ansible_scp_if_ssh
            version_added: '2.7'
      use_tty:
        version_added: '2.5'
        default: 'yes'
        description: add -tt to ssh commands to force tty allocation.
        env: [{name: ANSIBLE_SSH_USETTY}]
        ini:
        - {key: usetty, section: ssh_connection}
        type: bool
        vars:
          - name: ansible_ssh_use_tty
            version_added: '2.7'
      timeout:
        default: 10
        description:
            - This is the default amount of time we will wait while establishing an SSH connection.
            - It also controls how long we can wait to access reading the connection once established (select on the socket).
        env:
            - name: ANSIBLE_TIMEOUT
            - name: ANSIBLE_SSH_TIMEOUT
              version_added: '2.11'
        ini:
            - key: timeout
              section: defaults
            - key: timeout
              section: ssh_connection
              version_added: '2.11'
        vars:
          - name: ansible_ssh_timeout
            version_added: '2.11'
        cli:
          - name: timeout
        type: integer
      pkcs11_provider:
        version_added: '2.12'
        default: ""
        description:
          - "PKCS11 SmartCard provider such as opensc, example: /usr/local/lib/opensc-pkcs11.so"
          - Requires sshpass version 1.06+, sshpass must support the -P option.
        env: [{name: ANSIBLE_PKCS11_PROVIDER}]
        ini:
          - {key: pkcs11_provider, section: ssh_connection}
        vars:
          - name: ansible_ssh_pkcs11_provider
'''

class Connection(SSHConnection):
    ''' ssh based connections for powershell via packer'''

    transport = 'packer'
    has_pipelining = True
    become_methods = []
    allow_executable = False
    module_implementation_preferences = ('.ps1', '')

    def __init__(self, *args, **kwargs):
        super(Connection, self).__init__(*args, **kwargs)
