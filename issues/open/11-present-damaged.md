# `present_with_damage`

In addition to `present`, `softbuffer` provides a `present_with_damage`
function, that allows you to specify which regions of the image need to be
re-displayed. 

It also exposes an `age` function that can be used to see how old the
currently-displayed surface is. (read the docs for this one)

implement and expose these functions, and then take advantage of it in the `paint` demo
by only blitting the parts of the image that are necessary, and then reporting them via
`present_with_damage`.

