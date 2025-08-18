{
  programs.nvf.settings.vim.keymaps = [
    {
      mode = "";
      key = "H";
      action = "^";
    }
    {
      mode = "";
      key = "L";
      action = "$";
    }
    {
      mode = "";
      key = "J";
      action = "}";
    }
    {
      mode = "";
      key = "K";
      action = "{";
    }
    {
      mode = "v";
      key = "J";
      action = ":m '>+1<CR>gv=gv";
    }
    {
      mode = "v";
      key = "K";
      action = ":m '<-2<CR>gv=gv";
    }
    {
      mode = "v";
      key = "<";
      action = "<gv";
    }
    {
      mode = "v";
      key = ">";
      action = ">gv";
    }
    {
      mode = "";
      key = "<C-h>";
      action = "<C-w><C-h>";
      desc = "Move to left window";
    }
    {
      mode = "";
      key = "<C-l>";
      action = "<C-w><C-l>";
      desc = "Move to right window";
    }
    {
      mode = "";
      key = "<C-j>";
      action = "<C-w><C-j>";
      desc = "Move to lower window";
    }
    {
      mode = "";
      key = "<C-k>";
      action = "<C-w><C-k>";
      desc = "Move to upper window";
    }
    {
      mode = "n";
      key = "<Esc>";
      action = "<cmd>nohlsearch<CR>";
    }
    {
      mode = "n";
      key = "<C-e>";
      action = "<cmd>Neotree toggle<CR>";
      desc = "Explorer NeoTree (cwd)";
    }
    {
      mode = "n";
      key = "<leader>sp";
      action = "<cmd>Telescope persisted<CR>";
      desc = "[P]ersisted sessions";
    }
    {
      mode = ["n" "v"];
      key = "<leader>aa";
      action = "<cmd>CopilotChatToggle<CR>";
      desc = "Toggle Copilot";
    }
    {
      mode = ["n" "v"];
      key = "<leader>ax";
      action = "<cmd>CopilotChatReset<CR>";
      desc = "Clear Copilot";
    }
    {
      mode = ["n" "v"];
      key = "<leader>ap";
      action = "<cmd>CopilotChatPrompts<CR>";
      desc = "Copilot Prompt Action";
    }
    {
      mode = ["n" "v"];
      key = "<leader>ac";
      action = "<cmd>ClaudeCode<CR>";
      desc = "Toggle Claude Code";
    }
    {
      mode = "n";
      key = "<leader>X";
      action = "<cmd>XcodebuildPicker<CR>";
      desc = "[X]code picker";
    }
    {
      mode = "n";
      key = "<leader>xf";
      action = "<cmd>XcodebuildProjectManager<CR>";
      desc = "[X]code Project Manager";
    }
    {
      mode = "n";
      key = "<leader>rb";
      action = "<cmd>XcodebuildBuild<CR>";
      desc = "Run Xcode [B]uild";
    }
    {
      mode = "n";
      key = "<leader>rB";
      action = "<cmd>XcodebuildBuildForTesting<CR>";
      desc = "Run Xcode [B]uild Tests";
    }
    {
      mode = "n";
      key = "<leader>rr";
      action = "<cmd>XcodebuildBuildRun<CR>";
      desc = "Xcode Build and [R]un";
    }
    {
      mode = "n";
      key = "<leader>rd";
      action = "<cmd>XcodebuildBuildDebug<CR>";
      desc = "Xcode [D]ebug";
    }
    {
      mode = "n";
      key = "<leader>rl";
      action = "<cmd>XcodebuildToggleLogs<CR>";
      desc = "Xcode [L]ogs";
    }
    {
      mode = "n";
      key = "<leader>rP";
      action = "<cmd>XcodebuildPreviewGenerateAndShow<CR>";
      desc = "Xcode Generate [P]review";
    }
    {
      mode = "n";
      key = "<leader>rp";
      action = "<cmd>XcodebuildPreviewToggle<CR>";
      desc = "Xcode Toggle [P]review";
    }
    {
      mode = "n";
      key = "<leader>rD";
      action = "<cmd>XcodebuildSelectDevice<CR>";
      desc = "Xcode Select [D]evice";
    }
    {
      mode = "n";
      key = "<leader>rq";
      action = "<cmd>XcodebuildQucikfixLine<CR>";
      desc = "Xcode [Q]uickfix";
    }
    {
      mode = "n";
      key = "<leader>ra";
      action = "<cmd>XcodebuildCodeActions<CR>";
      desc = "Xcode Code [A]ction";
    }
  ];
}
