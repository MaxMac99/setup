{
  inputs,
  pkgs,
  ...
}: let
  inherit (inputs.nvf.lib.nvim.dag) entryAfter;
in {
  programs.nvf.settings.vim = {
    treesitter = {
      grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
        jinja
        jinja_inline
      ];

      # Highlight the language templated by a jinja file, inferred from its
      # inner extension (e.g. `nginx.conf.jinja` -> nginx, `app.js.jinja2` ->
      # javascript). See the `jinja-base-language!` directive below.
      queries = [
        {
          type = "injections";
          loadtype = "extends";
          filetypes = ["jinja"];
          query = ''
            ((content) @injection.content
              (#jinja-base-language!)
              (#set! injection.combined))
          '';
        }
      ];
    };

    filetype.extension = {
      jinja = "jinja";
      jinja2 = "jinja";
      j2 = "jinja";
    };

    luaConfigRC.jinjaBaseLanguage = entryAfter ["basic"] ''
      -- Jinja files carry no indication of what they template, so the base
      -- language for treesitter injection is inferred from the extension
      -- that precedes .jinja/.jinja2/.j2 (nginx.conf.jinja -> nginx). Files
      -- with no inner extension (e.g. plain `foo.jinja`), or where detection
      -- guesses wrong, can be corrected with :JinjaBase <language>.
      local jinja_extensions = {jinja = true, jinja2 = true, j2 = true}

      local function detect_jinja_base_language(bufnr)
        local name = vim.api.nvim_buf_get_name(bufnr)
        local ext = name:match("%.([%w_]+)$")
        if not ext or not jinja_extensions[ext] then
          return nil
        end
        local stripped = name:sub(1, #name - #ext - 1)
        local ft = vim.filetype.match({filename = stripped})
        return ft and vim.treesitter.language.get_lang(ft) or nil
      end

      -- `source` is the bufnr when running against a live buffer (always the
      -- case here: jinja files are only ever real files, never strings).
      vim.treesitter.query.add_directive("jinja-base-language!", function(_, _, source, _, metadata)
        if type(source) ~= "number" then
          return
        end
        local lang = vim.b[source].jinja_base_language
        if lang == nil then
          lang = detect_jinja_base_language(source) or false
          vim.b[source].jinja_base_language = lang
        end
        if lang then
          metadata["injection.language"] = lang
        end
      end, {force = true})

      vim.api.nvim_create_user_command("JinjaBase", function(opts)
        local buf = vim.api.nvim_get_current_buf()
        vim.b[buf].jinja_base_language = opts.args ~= "" and opts.args or false
        -- Buffer variable changes don't invalidate the parser's cached
        -- injection regions on their own; force it, then reparse.
        local ok, parser = pcall(vim.treesitter.get_parser, buf, "jinja")
        if ok then
          parser:invalidate(true)
          parser:parse(true)
        end
        vim.notify("jinja base language: " .. tostring(vim.b[buf].jinja_base_language))
      end, {
        nargs = "?",
        desc = "Set (or clear, with no argument) the language templated by this jinja buffer",
      })
    '';
  };
}
