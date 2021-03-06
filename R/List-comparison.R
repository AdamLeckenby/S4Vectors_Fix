### =========================================================================
### Comparing and ordering List objects
### -------------------------------------------------------------------------
###


### Method signatures for binary comparison operators.
.OP2_SIGNATURES <- list(
    c("List", "List"),
    c("List", "list"),
    c("list", "List")
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### pcompareRecursively()
###
### NOT exported!
###
### By default, List objects pcompare recursively. Exceptions to the rule
### (e.g. Ranges, XString, etc...) must define a "pcompareRecursively" method
### that returns FALSE.
###

setGeneric("pcompareRecursively",
    function(x) standardGeneric("pcompareRecursively")
)

setMethod("pcompareRecursively", "List", function(x) TRUE)
setMethod("pcompareRecursively", "list", function(x) TRUE)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### .op1_apply() and .op2_apply() internal helpers
###

### Apply a unary operator.
.op1_apply <- function(OP1, x, ..., ANS_CONSTRUCTOR)
{
    comp_rec_x <- pcompareRecursively(x)
    if (!comp_rec_x) {
        OP1_Vector_method <- selectMethod(OP1, "Vector")
        return(OP1_Vector_method(x, ...))
    }
    compress_ans <- !is(x, "SimpleList")
    ## Note that we should just be able to do
    ##   y <- lapply(x, OP1, ...)
    ## instead of the extremely obfuscated form below (which, in a bug-free
    ## world, should be equivalent to the simple form above).
    ## However, because of a regression in R 3.4.2, using the simple form
    ## above doesn't seem to work properly if OP1 is a generic function with
    ## dispatch on ... (e.g. order()). The form below seems to work though,
    ## so we use it as a temporary workaround.
    y <- lapply(x, function(xi) do.call(OP1, list(xi, ...)))
    ANS_CONSTRUCTOR(y, compress=compress_ans)
}

### Apply a binary operator.
.op2_apply <- function(OP2, x, y, ..., ANS_CONSTRUCTOR)
{
    comp_rec_x <- pcompareRecursively(x)
    comp_rec_y <- pcompareRecursively(y)
    if (!(comp_rec_x || comp_rec_y)) {
        OP2_Vector_method <- selectMethod(OP2, c("Vector", "Vector"))
        return(OP2_Vector_method(x, y, ...))
    }
    if (!comp_rec_x)
        x <- list(x)
    if (!comp_rec_y)
        y <- list(y)
    compress_ans <- !((is(x, "SimpleList") || is.list(x)) &&
                      (is(y, "SimpleList") || is.list(y)))
    x_len <- length(x)
    y_len <- length(y)
    if (x_len == 0L || y_len == 0L) {
        ans <- ANS_CONSTRUCTOR(compress=compress_ans)
    } else {
        ans <- ANS_CONSTRUCTOR(mapply(OP2, x, y, MoreArgs=list(...),
                                      SIMPLIFY=FALSE, USE.NAMES=FALSE),
                               compress=compress_ans)
    }
    ## 'ans' is guaranteed to have the length of 'x' or 'y'.
    x_names <- names(x)
    y_names <- names(y)
    if (!(is.null(x_names) && is.null(y_names))) {
        ans_len <- length(ans)
        if (x_len != y_len) {
            if (x_len == ans_len) {
                ans_names <- x_names
            } else {
                ans_names <- y_names
            }
        } else {
            if (is.null(x_names)) {
                ans_names <- y_names
            } else {
                ans_names <- x_names
            }
        }
        names(ans) <- ans_names
    }
    ans
}


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### Element-wise (aka "parallel") comparison of 2 List objects.
###

setMethods("pcompare", .OP2_SIGNATURES,
           function(x, y) .op2_apply(pcompare, x, y, ANS_CONSTRUCTOR=IRanges::IntegerList)
)

setMethods("==", .OP2_SIGNATURES,
           function(e1, e2) .op2_apply(`==`, e1, e2, ANS_CONSTRUCTOR=IRanges::LogicalList)
)

setMethods("<=", .OP2_SIGNATURES,
           function(e1, e2) .op2_apply(`<=`, e1, e2, ANS_CONSTRUCTOR=IRanges::LogicalList)
)

### The remaining comparison binary operators (!=, >=, <, >) will work
### out-of-the-box on List objects thanks to the "!" methods below and to the
### methods for Vector objects.
setMethod("!", "List",
    function(x)
    {
        if (is(x, "RleList")) {
            ANS_CONSTRUCTOR <- IRanges::RleList
        } else {
            ANS_CONSTRUCTOR <- IRanges::LogicalList
        }
        .op1_apply(`!`, x, ANS_CONSTRUCTOR=ANS_CONSTRUCTOR)
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### match()
###

setMethods("match", .OP2_SIGNATURES,
    function(x, table, nomatch=NA_integer_, incomparables=NULL, ...)
    {
        if (is(x, "RleList")) {
            ANS_CONSTRUCTOR <- IRanges::RleList
        } else {
            ANS_CONSTRUCTOR <- IRanges::IntegerList
        }
        .op2_apply(match, x, table,
                   nomatch=nomatch, incomparables=incomparables, ...,
                   ANS_CONSTRUCTOR=ANS_CONSTRUCTOR)
    }
)

### 2 of the 3 "match" methods defined above have signatures List,list and
### List,List and therefore are more specific than the 2 methods below.
### So in the methods below 'table' is guaranteed to be a vector that is not
### a list or a Vector that is not a List.
setMethods("match", list(c("List", "vector"), c("List", "Vector")),
    function(x, table, nomatch=NA_integer_, incomparables=NULL, ...)
    {
        match(x, list(table),
              nomatch=nomatch, incomparables=incomparables, ...)
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### duplicated() & unique()
###

.duplicated.List <- function(x, incomparables=FALSE,
                               fromLast=FALSE, ...)
{
    .op1_apply(duplicated, x,
               incomparables=incomparables, fromLast=fromLast, ...,
               ANS_CONSTRUCTOR=IRanges::LogicalList)
}
setMethod("duplicated", "List", .duplicated.List)

.unique.List <- function(x, incomparables=FALSE, ...)
{
    if (!pcompareRecursively(x))
        return(callNextMethod())
    i <- !duplicated(x, incomparables=incomparables, ...)  # LogicalList
    x[i]
}
setMethod("unique", "List", .unique.List)

### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### %in%
###

### The "%in%" method for Vector objects calls is.na() internally.
setMethod("is.na", "List",
    function(x)
    {
        if (is(x, "RleList")) {
            ANS_CONSTRUCTOR <- IRanges::RleList
        } else {
            ANS_CONSTRUCTOR <- IRanges::LogicalList
        }
        .op1_apply(is.na, x, ANS_CONSTRUCTOR=ANS_CONSTRUCTOR)
    }
)


### - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
### order() and related methods.
###

setMethod("order", "List",
    function(..., na.last=TRUE, decreasing=FALSE,
                  method=c("auto", "shell", "radix"))
    {
        args <- list(...)
        if (length(args) != 1L)
            stop("\"order\" method for List objects ",
                 "can only take one input object")
        .op1_apply(order, args[[1L]],
                   na.last=na.last, decreasing=decreasing, method=method,
                   ANS_CONSTRUCTOR=IRanges::IntegerList)
    }
)

.sort.List <- function(x, decreasing=FALSE, na.last=NA)
{
    if (!pcompareRecursively(x))
        return(callNextMethod())
    i <- order(x, na.last=na.last, decreasing=decreasing)  # IntegerList
    x[i]
}
setMethod("sort", "List", .sort.List)

setMethod("rank", "List",
    function(x, na.last=TRUE,
             ties.method=c("average", "first", "random", "max", "min"))
    {
        .op1_apply(rank, x,
                   na.last=na.last, ties.method=ties.method,
                   ANS_CONSTRUCTOR=IRanges::IntegerList)
    }
)

setMethod("is.unsorted", "List", function(x, na.rm = FALSE, strictly = FALSE) {
              vapply(x, is.unsorted, logical(1L), na.rm=na.rm,
                     strictly=strictly)
          })

