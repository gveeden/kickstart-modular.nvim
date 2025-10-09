---@param params table Table containing message and allowed_words
---@return table The filtered message
local function filter_out_messages(params)
  local message = params.message

  local allowed = params.allowed_words

  for key, _ in pairs(message) do
    if not vim.tbl_contains(allowed, key) then
      message[key] = nil
    end
  end
  return message
end

return {
  'olimorris/codecompanion.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
    'ravitemer/mcphub.nvim',
  },
  opts = {
    adapters = {
      acp = {
        claude_code = function()
          return require('codecompanion.adapters').extend('claude_code', {
            env = {
              CLAUDE_CODE_OAUTH_TOKEN = '',
            },
          })
        end,
      },
      qwen3 = function()
        return require('codecompanion.adapters').extend('ollama', {
          name = 'qwen3',
          schema = {
            model = {
              default = 'qwen3:8b',
            },
          },
        })
      end,
      deepseek = function()
        return require('codecompanion.adapters').extend('ollama', {
          name = 'deepseek',
          schema = {
            model = {
              default = 'deepseek-r1:32b',
            },
          },
        })
      end,
      gemma3n = function()
        return require('codecompanion.adapters').extend('ollama', {
          name = 'gemma3n',
          schema = {
            model = {
              default = 'gemma3n:e4b',
            },
          },
        })
      end,
      anthropic_with_bearer_token = function()
        local utils = require 'codecompanion.utils.adapters'
        local tokens = require 'codecompanion.utils.tokens'

        return require('codecompanion.adapters').extend('anthropic', {
          env = {
            bearer_token = '',
          },
          headers = {
            ['content-type'] = 'application/json',
            ['authorization'] = 'Bearer ${bearer_token}',
            ['anthropic-version'] = '2023-06-01',
            ['anthropic-beta'] = 'claude-code-20250219,oauth-2025-04-20,interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14',
          },
          handlers = {
            setup = function(self)
              -- Same as current setup function but removing the additional headers being added

              if self.headers and self.headers['x-api-key'] then
                self.headers['x-api-key'] = nil
              end

              if self.opts and self.opts.stream then
                self.parameters.stream = true
              end

              local model = self.schema.model.default
              local model_opts = self.schema.model.choices[model]
              if model_opts and model_opts.opts then
                self.opts = vim.tbl_deep_extend('force', self.opts, model_opts.opts)
                if not model_opts.opts.has_vision then
                  self.opts.vision = false
                end
              end

              return true
            end,

            form_messages = function(self, messages)
              -- Same as current form_message but adding Claude Code system message at the first system message

              local has_tools = false

              local system = vim
                .iter(messages)
                :filter(function(msg)
                  return msg.role == 'system'
                end)
                :map(function(msg)
                  return {
                    type = 'text',
                    text = msg.content,
                    cache_control = nil,
                  }
                end)
                :totable()

              -- Add the Claude Code system message at the beginning (required to make it work)
              table.insert(system, 1, {
                type = 'text',
                text = "You are Claude Code, Anthropic's official CLI for Claude.",
                cache_control = {
                  type = 'ephemeral',
                },
              })

              system = next(system) and system or nil

              messages = vim
                .iter(messages)
                :filter(function(msg)
                  return msg.role ~= 'system'
                end)
                :totable()

              messages = vim.tbl_map(function(message)
                if message.opts and message.opts.tag == 'image' and message.opts.mimetype then
                  if self.opts and self.opts.vision then
                    message.content = {
                      {
                        type = 'image',
                        source = {
                          type = 'base64',
                          media_type = message.opts.mimetype,
                          data = message.content,
                        },
                      },
                    }
                  else
                    return nil
                  end
                end

                message = filter_out_messages {
                  message = message,
                  allowed_words = { 'content', 'role', 'reasoning', 'tool_calls' },
                }

                if message.role == self.roles.user or message.role == self.roles.llm then
                  if message.role == self.roles.user and message.content == '' then
                    message.content = '<prompt></prompt>'
                  end

                  if type(message.content) == 'string' then
                    message.content = {
                      { type = 'text', text = message.content },
                    }
                  end
                end

                if message.tool_calls and vim.tbl_count(message.tool_calls) > 0 then
                  has_tools = true
                end

                if message.role == 'tool' then
                  message.role = self.roles.user
                end

                if has_tools and message.role == self.roles.llm and message.tool_calls then
                  message.content = message.content or {}
                  for _, call in ipairs(message.tool_calls) do
                    table.insert(message.content, {
                      type = 'tool_use',
                      id = call.id,
                      name = call['function'].name,
                      input = vim.json.decode(call['function'].arguments),
                    })
                  end
                  message.tool_calls = nil
                end

                if message.reasoning and type(message.content) == 'table' then
                  table.insert(message.content, 1, {
                    type = 'thinking',
                    thinking = message.reasoning.content,
                    signature = message.reasoning._data.signature,
                  })
                end

                return message
              end, messages)

              messages = utils.merge_messages(messages)

              if has_tools then
                for _, m in ipairs(messages) do
                  if m.role == self.roles.user and m.content and m.content ~= '' then
                    if type(m.content) == 'table' and m.content.type then
                      m.content = { m.content }
                    end

                    if type(m.content) == 'table' and vim.islist(m.content) then
                      local consolidated = {}
                      for _, block in ipairs(m.content) do
                        if block.type == 'tool_result' then
                          local prev = consolidated[#consolidated]
                          if prev and prev.type == 'tool_result' and prev.tool_use_id == block.tool_use_id then
                            prev.content = prev.content .. block.content
                          else
                            table.insert(consolidated, block)
                          end
                        else
                          table.insert(consolidated, block)
                        end
                      end
                      m.content = consolidated
                    end
                  end
                end
              end

              local breakpoints_used = 0
              for i = #messages, 1, -1 do
                local msgs = messages[i]
                if msgs.role == self.roles.user then
                  for _, msg in ipairs(msgs.content) do
                    if msg.type ~= 'text' or msg.text == '' then
                      goto continue
                    end
                    if tokens.calculate(msg.text) >= self.opts.cache_over and breakpoints_used < self.opts.cache_breakpoints then
                      msg.cache_control = { type = 'ephemeral' }
                      breakpoints_used = breakpoints_used + 1
                    end
                    ::continue::
                  end
                end
              end
              if system and breakpoints_used < self.opts.cache_breakpoints then
                for _, prompt in ipairs(system) do
                  if breakpoints_used < self.opts.cache_breakpoints then
                    prompt.cache_control = { type = 'ephemeral' }
                    breakpoints_used = breakpoints_used + 1
                  end
                end
              end

              return { system = system, messages = messages }
            end,
          },
        })
      end,
    },
    opts = {
      log_level = 'DEBUG',
    },
    strategies = {
      inline = {
        adapter = 'gemma3n',
      },
      cmd = {
        adapter = 'gemma3n',
      },

      chat = {
        adapter = 'claude_code',
        --- adapter = 'qwen3',
        tools = {
          groups = {
            ['full_stack_dev'] = {
              description = 'Full Stack Developer - Can run code, edit code and modify files',
              prompt = "I'm giving you access to the ${tools} to help you perform coding tasks",
              tools = {
                'cmd_runner',
                'create_file',
                'file_search',
                'get_changed_files',
                'grep_search',
                'insert_edit_into_file',
                'list_code_usages',
                'read_file',
              },
              opts = {
                collapse_tools = true,
              },
            },
            ['files'] = {
              description = 'Tools related to creating, reading and editing files',
              prompt = "I'm giving you access to ${tools} to help you perform file operations",
              tools = {
                'create_file',
                'file_search',
                'get_changed_files',
                'grep_search',
                'insert_edit_into_file',
                'read_file',
              },
              opts = {
                collapse_tools = true,
              },
            },
          },
          -- Tools
          ['cmd_runner'] = {
            callback = 'strategies.chat.tools.catalog.cmd_runner',
            description = 'Run shell commands initiated by the LLM',
            opts = {
              requires_approval = true,
            },
          },
          ['create_file'] = {
            callback = 'strategies.chat.tools.catalog.create_file',
            description = 'Create a file in the current working directory',
            opts = {
              requires_approval = true,
            },
          },
          ['fetch_webpage'] = {
            callback = 'strategies.chat.tools.catalog.fetch_webpage',
            description = 'Fetches content from a webpage',
            opts = {
              adapter = 'jina',
            },
          },
          ['file_search'] = {
            callback = 'strategies.chat.tools.catalog.file_search',
            description = 'Search for files in the current working directory by glob pattern',
            opts = {
              max_results = 500,
            },
          },
          ['get_changed_files'] = {
            callback = 'strategies.chat.tools.catalog.get_changed_files',
            description = 'Get git diffs of current file changes in a git repository',
            opts = {
              max_lines = 1000,
            },
          },
          ['grep_search'] = {
            callback = 'strategies.chat.tools.catalog.grep_search',
            enabled = function()
              -- Currently this tool only supports ripgrep
              return vim.fn.executable 'rg' == 1
            end,
            description = 'Search for text in the current working directory',
            opts = {
              max_results = 100,
              respect_gitignore = true,
            },
          },
          ['insert_edit_into_file'] = {
            callback = 'strategies.chat.tools.catalog.insert_edit_into_file',
            description = 'Insert code into an existing file',
            opts = {
              patching_algorithm = 'strategies.chat.tools.catalog.helpers.patch',
              requires_approval = { -- Require approval before the tool is executed?
                buffer = false, -- For editing buffers in Neovim
                file = true, -- For editing files in the current working directory
              },
              user_confirmation = true, -- Require confirmation from the user before accepting the edit?
            },
          },
          ['next_edit_suggestion'] = {
            callback = 'strategies.chat.tools.catalog.next_edit_suggestion',
            description = 'Suggest and jump to the next position to edit',
          },
          ['read_file'] = {
            callback = 'strategies.chat.tools.catalog.read_file',
            description = 'Read a file in the current working directory',
          },
          ['search_web'] = {
            callback = 'strategies.chat.tools.catalog.search_web',
            description = 'Search the web for information',
            opts = {
              adapter = 'tavily', -- tavily
              opts = {
                -- Tavily options
                search_depth = 'advanced',
                topic = 'general',
                chunks_per_source = 3,
                max_results = 5,
              },
            },
          },
          ['list_code_usages'] = {
            callback = 'strategies.chat.tools.catalog.list_code_usages',
            description = 'Find code symbol context',
          },
          opts = {
            auto_submit_errors = false, -- Send any errors to the LLM automatically?
            auto_submit_success = true, -- Send any successful output to the LLM automatically?
            folds = {
              enabled = true, -- Fold tool output in the buffer?
              failure_words = { -- Words that indicate an error in the tool output. Used to apply failure highlighting
                'cancelled',
                'error',
                'failed',
                'incorrect',
                'invalid',
                'rejected',
              },
            },
            ---Tools and/or groups that are always loaded in a chat buffer
            ---@type string[]
            default_tools = {},

            system_prompt = {
              enabled = true, -- Enable the tools system prompt?
              replace_main_system_prompt = false, -- Replace the main system prompt with the tools system prompt?

              ---The tool system prompt
              ---@param args { tools: string[]} The tools available
              ---@return string
              prompt = function(args)
                return [[<instructions>
You are a highly sophisticated automated coding agent with expert-level knowledge across many different programming languages and frameworks.
The user will ask a question, or ask you to perform a task, and it may require lots of research to answer correctly. There is a selection of tools that let you perform actions or retrieve helpful context to answer the user's question.
You will be given some context and attachments along with the user prompt. You can use them if they are relevant to the task, and ignore them if not.
If you can infer the project type (languages, frameworks, and libraries) from the user's query or the context that you have, make sure to keep them in mind when making changes.
If the user wants you to implement a feature and they have not specified the files to edit, first break down the user's request into smaller concepts and think about the kinds of files you need to grasp each concept.
If you aren't sure which tool is relevant, you can call multiple tools. You can call tools repeatedly to take actions or gather as much context as needed until you have completed the task fully. Don't give up unless you are sure the request cannot be fulfilled with the tools you have. It's YOUR RESPONSIBILITY to make sure that you have done all you can to collect necessary context.
Don't make assumptions about the situation - gather context first, then perform the task or answer the question.
Think creatively and explore the workspace in order to make a complete fix.
Don't repeat yourself after a tool call, pick up where you left off.
NEVER print out a codeblock with a terminal command to run unless the user asked for it.
You don't need to read a file if it's already provided in context.
</instructions>
<toolUseInstructions>
When using a tool, follow the json schema very carefully and make sure to include ALL required properties.
Always output valid JSON when using a tool.
If a tool exists to do a task, use the tool instead of asking the user to manually take an action.
If you say that you will take an action, then go ahead and use the tool to do it. No need to ask permission.
Never use a tool that does not exist. Use tools using the proper procedure, DO NOT write out a json codeblock with the tool inputs.
Never say the name of a tool to a user. For example, instead of saying that you'll use the insert_edit_into_file tool, say "I'll edit the file".
If you think running multiple tools can answer the user's question, prefer calling them in parallel whenever possible.
When invoking a tool that takes a file path, always use the file path you have been given by the user or by the output of a tool.
</toolUseInstructions>
<outputFormatting>
Use proper Markdown formatting in your answers. When referring to a filename or symbol in the user's workspace, wrap it in backticks.
Any code block examples must be wrapped in four backticks with the programming language.
<example>
````languageId
// Your code here
````
</example>
The languageId must be the correct identifier for the programming language, e.g. python, javascript, lua, etc.
If you are providing code changes, use the insert_edit_into_file tool (if available to you) to make the changes directly instead of printing out a code block with the changes.
</outputFormatting>]]
              end,
            },

            tool_replacement_message = 'the ${tool} tool', -- The message to use when replacing tool names in the chat buffer
          },
        },
        variables = {
          ['buffer'] = {
            callback = 'strategies.chat.variables.buffer',
            description = 'Share the current buffer with the LLM',
            opts = {
              contains_code = true,
              default_params = 'watch', -- watch|pin
              has_params = true,
              excluded = {
                buftypes = {
                  'nofile',
                  'quickfix',
                  'prompt',
                  'popup',
                },
                fts = {
                  'codecompanion',
                  'help',
                  'terminal',
                },
              },
            },
          },
          ['lsp'] = {
            callback = 'strategies.chat.variables.lsp',
            description = 'Share LSP information and code for the current buffer',
            opts = {
              contains_code = true,
            },
          },
          ['viewport'] = {
            callback = 'strategies.chat.variables.viewport',
            description = 'Share the code that you see in Neovim with the LLM',
            opts = {
              contains_code = true,
            },
          },
        },
      },
    },
  },
}
