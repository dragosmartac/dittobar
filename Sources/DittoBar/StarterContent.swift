import Foundation

/// Markdown the app writes into the cheat-sheet folder: the starter sheets
/// created on first launch and the template for new sheets.
enum StarterContent {
    /// Prepended to every sheet this app creates. The parser skips HTML
    /// comments, so this block can safely show headings and code fences.
    static let instructions = """
    <!--
    How this file works

      # Title         The name displayed in the list of tabs
      ## Section      An optional separator inside the tab
      ### Entry       An interactive component within the tab

      Entry types:
      1. Command
         Any non-empty fenced block except ```url ...```.
      2. URL
         A non-empty ```url ...``` block.
      3. Note
         Content without a non-empty fenced block.

    Description formatting

      Descriptions support inline Markdown: `code`, **bold**, *italic*,
      ~~strikethrough~~, and [links](https://example.com).

    Variables

      To create a variable, use the following syntax in a code block or
      in a description: {{name=default}}.

      The default value is optional. You can reuse a variable by writing
      {{name}} wherever needed. You only need to define its default value once.

    Anything inside an HTML comment, like this block, is ignored. The app
    reloads this file automatically when you save it.
    -->
    """

    static let vimSheet = withInstructions("""
    # Vim

    ### Move left, down, up, right
    Basic Normal-mode movement.

    ```text
    h  j  k  l
    ```

    ### Move by word
    Next word, previous word, and end of word.

    ```text
    w  b  e
    ```

    ### Move within a line
    Start, first non-blank character, and end of line.

    ```text
    0  ^  $
    ```

    ### Jump through the file
    First line, last line, or a specific line.

    ```text
    gg  G  :{line}
    ```

    ### Enter Insert mode
    Before/after the cursor, or on a new line below/above.

    ```text
    i  a  o  O
    ```

    ### Delete, change, or yank a motion
    Combine an operator with a motion; double it for the whole line.

    ```text
    d{motion}  c{motion}  y{motion}  dd  cc  yy
    ```

    ### Paste
    Paste after or before the cursor.

    ```text
    p  P
    ```

    ### Undo, redo, and repeat

    ```text
    u  Ctrl-r  .
    ```

    ### Search and repeat
    Search forward/backward, then move to the next/previous match.

    ```text
    /pattern  ?pattern  n  N
    ```

    ### Replace throughout the file
    Confirm each replacement.

    ```vim
    :%s/old/new/gc
    ```

    ### Select text visually
    Character, line, or block selection.

    ```text
    v  V  Ctrl-v
    ```

    ### Save and quit

    ```vim
    :w  :q  :wq  :q!
    ```

    ### Switch buffers
    Next, previous, list, or choose a buffer.

    ```vim
    :bn  :bp  :ls  :b {name}
    ```

    ### Record and replay a macro
    Record into register a, stop, then replay it.

    ```text
    qa  q  @a  @@
    ```
    """)

    static let gitSheet = withInstructions("""
    # Git

    ### See repository status
    Show the current branch and staged, unstaged, and untracked files.

    ```sh
    git status --short --branch
    ```

    ### Review unstaged changes
    Inspect changes in the working tree before staging them.

    ```sh
    git diff
    ```

    ### Review staged changes
    Inspect exactly what will be included in the next commit.

    ```sh
    git diff --staged
    ```

    ### Stage selected changes
    Interactively choose individual hunks to stage.

    ```sh
    git add --patch
    ```

    ### Commit staged changes
    Create a commit with a concise message. Copying this one opens a form, because
    `{{name=default}}` marks an editable variable.

    ```sh
    git commit -m "{{message=Describe the change}}"
    ```

    ### Amend the latest commit
    Add staged changes without changing the commit message.

    ```sh
    git commit --amend --no-edit
    ```

    ### View compact history
    Show a decorated branch graph for all local and remote branches.

    ```sh
    git log --oneline --graph --decorate --all
    ```

    ### Create and switch to a branch
    Repeating a variable name reuses one field for every occurrence.

    ```sh
    git switch -c {{branch=feature/my-change}} && git push -u origin {{branch}}
    ```

    ### Switch branches

    ```sh
    git switch {{branch=main}}
    ```

    ### Update the current branch
    Fetch from its remote and replay local commits on top.

    ```sh
    git pull --rebase
    ```

    ### Push a new branch
    Publish the branch and remember its upstream.

    ```sh
    git push -u origin HEAD
    ```

    ### Temporarily stash changes
    Include untracked files and label the stash for easier recovery.

    ```sh
    git stash push -u -m "work in progress"
    ```

    ### Restore the latest stash
    Apply the most recent stash and remove it from the stash list.

    ```sh
    git stash pop
    ```

    ### Unstage a file
    Keep the working-tree changes while removing the file from the index.

    ```sh
    git restore --staged <file>
    ```

    ### Discard a file's changes
    Replace an unstaged file with its last committed version. This cannot be undone by Git.

    ```sh
    git restore <file>
    ```

    ### Revert a published commit
    Make a new commit that safely reverses an earlier commit.

    ```sh
    git revert <commit>
    ```

    ### Find a lost commit
    Inspect recent HEAD movements after a reset, rebase, or deleted branch.

    ```sh
    git reflog
    ```

    ### Show who changed each line

    ```sh
    git blame <file>
    ```

    ### Search commit messages

    ```sh
    git log --grep="{{text=fix}}" --oneline
    ```
    """)

    static func newSheet(named name: String) -> String {
        withInstructions("""
        # \(name)

        ### Command name
        Add an optional description here.

        ```sh
        command
        ```

        ### Command with a variable
        Copying this one opens a form with a single editable field.

        ```sh
        echo {{message=hello}}
        ```
        """)
    }

    private static func withInstructions(_ sheet: String) -> String {
        "\(instructions)\n\n\(sheet)"
    }
}
