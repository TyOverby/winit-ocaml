# Enum "undefined" means optional
subproject: wgpu code generator

When an enum type contains a constructor called "undefined", this means that 
functions which take such a parameter should be optional parameters, like so:
`let foo ?(my_optional_enum = My_optional_enum.Undefined)`.  

This should be done for functions, as well as the record `create` functions.
