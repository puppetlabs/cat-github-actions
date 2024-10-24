## Attention

Reviewdog/shellcheck is a third-party action that we have implemented in our testing workflows. As such,
if your repository has strict permission control, you might need to add it as a trusted action. Otherwise,
you might run into the following or similar errors:

`reviewdog/action-shellcheck@v1 is not allowed to be used in <your_repo>. Actions in this workflow must be: within a repository that belongs to your Enterprise account, created by GitHub, verified in the GitHub Marketplace, or matching the following: ruby/*, puppetlabs/*, docker://puppet/*, luchihoratiu/*, peter-evans/*.`
