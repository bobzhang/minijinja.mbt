///|
test "test_cycler" {
  assert_eq(
    render(
      (
        #|{% set c = cycler([1, 2]) -%}
        #|next(): {{ c.next() }}
        #|next(): {{ c.next() }}
        #|next(): {{ c.next() }}
        #|cycler: {{ c }}
      ),
    ),
    (
      #|next(): 1
      #|next(): 2
      #|next(): 1
      #|cycler: Cycler { items: [1, 2], pos: 1 }
    ),
  )
}

///|
test "test_joiner" {
  assert_eq(
    render(
      (
        #|{% set j = joiner() -%}
        #|first: [{{ j() }}]
        #|second: [{{ j() }}]
        #|joiner: {{ j }}
      ),
    ),
    (
      #|first: []
      #|second: [, ]
      #|joiner: Joiner { sep: ', ', used: true }
    ),
  )
  assert_eq(
    render(
      (
        #|{% set j = joiner('|') -%}
        #|first: [{{ j() }}]
        #|second: [{{ j() }}]
        #|joiner: {{ j }}
      ),
    ),
    (
      #|first: []
      #|second: [|]
      #|joiner: Joiner { sep: '|', used: true }
    ),
  )
}

///|
test "test_lispum" {
  assert_eq(
    render("{% set RAND_SEED = 42 %}{{ lipsum(5) }}"),
    (
      #|Nulla curae morbi nec gravida scelerisque habitant facilisi eros lectus molestie mattis neque dignissim. Convallis per ssociis erat ipsum pellentesque.
      #|
      #|Imperdiet enim egestas feugiat adipiscing sociosqu vulputate malesuada fames elit massa arcu eleifend porta morbi lectus. Aenean metus risus elit pede nec morbi hendrerit ssociis natoque gravida montes ssociis ante gravida dignissim. Congue sapien augue sociosqu ssociis aptent id ridiculus eu sed imperdiet enim aliquam hendrerit rutrum. Quisque bibendum neque ssociis porta mauris ssociis sociis facilisi gravida proin metus imperdiet luctus. Nam natoque pulvinar dolor sociosqu aptent at sociosqu placerat malesuada placerat et. Fusce aptent hymenaeos mauris leo elit morbi proin cum consectetuer cras ssociis lacus maecenas. Ad potenti duis ssociis ante hymenaeos mi dictum ligula dictum.
      #|
      #|Ridiculus ssociis ac habitasse ssociis maecenas lacinia diam faucibus porta diam magna. Mus laoreet mollis sociosqu ssociis mus mollis praesent ssociis molestie habitant inceptos. Sociosqu class congue eu luctus rhoncus dolor sem natoque mattis hymenaeos fusce nunc. Egestas habitant cum pulvinar parturient ssociis sociosqu metus mus aliquam libero nec platea curabitur orci nisi. Purus dapibus nunc arcu donec cursus ornare dui in porttitor potenti a nascetur. S nisi posuere pretium hac lacinia pulvinar senectus platea dis mattis semper condimentum convallis cursus dis. Mattis ssociis inceptos duis.
      #|
      #|Platea donec vsociis ssociis aliquet non ssociis sit placerat nostra lacus habitant ssociis. Phasellus hymenaeos arcu sit magnis dis at nisi cras curabitur sociosqu eget sociis cras. Aenean duis iaculis platea donec sociosqu lacus pretium ssociis pellentesque risus ssociis nam nonummy. Adipiscing rutrum in commodo non hac vsociis etiam vulputate sapien sociosqu potenti aliquam. Quis cras nostra senectus amet adipiscing duis aliquam semper etiam elementum. Ssociis mi in laoreet at sociis ssociis.
      #|
      #|Neque eros ssociis faucibus euismod est interdum nam quis condimentum dis natoque a ssociis nec. Duis erat mollis cubilia faucibus rhoncus pellentesque laoreet commodo mi imperdiet pede ssociis. Parturient lobortis ssociis quam lectus nec ac dui maecenas orci netus fringilla magnis curabitur justo. Sed porta phasellus molestie cubilia nunc luctus platea mattis platea nullam elementum cursus ornare. Ssociis scelerisque.
      #|
      #|
    ),
  )
  assert_eq(
    render("{% set RAND_SEED = 42 %}{{ lipsum(2, html=true) }}"),
    (
      #|<p>Nulla curae morbi nec gravida scelerisque habitant facilisi eros lectus molestie mattis neque dignissim. Convallis per ssociis erat ipsum pellentesque.</p>
      #|
      #|<p>Imperdiet enim egestas feugiat adipiscing sociosqu vulputate malesuada fames elit massa arcu eleifend porta morbi lectus. Aenean metus risus elit pede nec morbi hendrerit ssociis natoque gravida montes ssociis ante gravida dignissim. Congue sapien augue sociosqu ssociis aptent id ridiculus eu sed imperdiet enim aliquam hendrerit rutrum. Quisque bibendum neque ssociis porta mauris ssociis sociis facilisi gravida proin metus imperdiet luctus. Nam natoque pulvinar dolor sociosqu aptent at sociosqu placerat malesuada placerat et. Fusce aptent hymenaeos mauris leo elit morbi proin cum consectetuer cras ssociis lacus maecenas. Ad potenti duis ssociis ante hymenaeos mi dictum ligula dictum.</p>
      #|
      #|
    ),
  )
}

///|
test "test_randrange" {
  assert_eq(
    render("{% set RAND_SEED = 42 %}{{ randrange(10) }}|{{ randrange(10) }}"),
    "0|6",
  )
  assert_eq(render("{% set RAND_SEED = 42 %}{{ randrange(-50, 50) }}"), "-50")
}
