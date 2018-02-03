jQuery(document).ready(function ($) {
    window.kind_id = "";
    window.last_kind_id = "";

    $('.nav-sidebar').on('click', 'span', function() {
        $(this).closest('li').find('> .thumb').click();
    });

    function set_kind_id(id) {
        window.kind_id = id;
        console.log("Setting up this id: " + id);

        $(".category").addClass("disabled");
        $(".element").addClass("disabled");
        $("." + id).removeClass("disabled");

        if (window.last_kind_id !== id) {
            // Remove functions from GL that ES doesn't have and vice versa.
            let hide_elements = function () {
                $(this).addClass("hidden");

                let classList = $(this).attr('class').split(/\s+/);
                for (let i = 0; i < classList.length; i++) {
                    if (classList[i] === id) {
                        $(this).removeClass("hidden");
                        break;
                    }
                }
            };

            $(".element").each(hide_elements);
            $(".category").each(hide_elements);

            $(".categories > li").each(function () {
                let $el = $(this);
                if ($el.hasClass("expanded")) {
                    let bonsaiElement = $el.data("bonsai");
                    if (bonsaiElement) {
                        bonsaiElement.expand();
                    }
                }
            });

            window.last_kind_id = id;
        }
    }

    $(function () {

        $("#categories").bonsai();

        $("#versions_dropdown").selectmenu({
            change: function (event, ui) {
                set_kind_id(ui.item.value);
            }
        });

        set_kind_id(window.current_kind);
        $("#versions_dropdown").val(window.current_kind).selectmenu('refresh');

        // hack to run after bonsai is initailized
        setTimeout(function () {
            $(".open_me").each(function () {
                // copied from bonsai js to expand w/o animation
                let listItem = $(this);
                if (!listItem.data('subList'))
                    return;
                listItem.addClass('expanded').removeClass('collapsed');
                let subList = $(listItem.data('subList'));
                subList.css('height', 'auto');
            });
        }, 1);

    });
});