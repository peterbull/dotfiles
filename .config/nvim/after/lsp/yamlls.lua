return require('schema-companion').setup_client(
  require('schema-companion').adapters.yamlls.setup {
    sources = {
      -- Kubernetes matcher - automatically detects K8s resources
      require('schema-companion').sources.matchers.kubernetes.setup {
        version = 'master',
      },

      -- Use LSP's built-in schemas
      require('schema-companion').sources.lsp.setup(),

      -- Static schemas for manual selection
      require('schema-companion').sources.schemas.setup {
        {
          name = 'Kubernetes v1.28',
          uri = 'https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.28.0-standalone-strict/all.json',
        },
        {
          name = 'Docker Compose',
          uri = 'https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json',
        },
      },

      -- Option to clear schema
      require('schema-companion').sources.none.setup(),
    },
  },
  {
    -- Your yamlls configuration
    settings = {
      redhat = {
        telemetry = { enabled = false },
      },
      yaml = {
        format = { enable = true },
        validate = true,
        completion = true,
        hover = true,
      },
    },
  }
)
