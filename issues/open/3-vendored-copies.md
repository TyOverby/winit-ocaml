# Vendored copies

Right now, we have `winit` and `softbuffer` vendored.  It's hard to commit
changes here because they're set up to point at the upstream source on github. 

Using the `gh` tool, create forks of these projects and change the remotes of these 
vendored so that the git submodules can point to the forks.
