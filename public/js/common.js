//顶部弹出消息
(function(){
    var $popup_msg = $('#popup-msg'), 
    hideTimer = null, 
    hideInterval = 10000,
    minShowTime = 500, 
    startTime = 0,
    clearHideTimer = function(){
        if (hideTimer) {
            window.clearTimeout(hideTimer);
            hideTimer = null;
        }
    };

    $popup_msg.delegate('.close', 'click', function(event){
        event.preventDefault();
        $popup_msg.hide();

    });

    function popup_msg(msg, type)
    {
        type = type || 'error';

        if (type == 'succ') type = 'success';

        msg = 
        '<button type="button" class="close">&times;</button>' + 
        msg.replace(/<(?:div|p)[^>]*>/gi, '').replace(/<\/(?:div|p)>/gi, '<br/>').replace(/<br\/>\s*$/, '');

        $popup_msg.html(msg).show();
        $popup_msg.attr('class', 'alert alert-' + type);
        var left = ($(window).width() - ($popup_msg.attr('offsetWidth') || $popup_msg.prop('offsetWidth'))) / 2;
        $popup_msg.css('left', left);//.hide().slideDown();
        startTime = + new Date;
        clearHideTimer();

        if (type == 'success') {
            hideTimer = setTimeout(function(){ hide_msg() }, hideInterval);
        }
    }
    
    function hide_msg()
    {
        clearHideTimer();

        var showTime = + new Date - startTime;
        if (showTime < minShowTime) {
            hideTimer = setTimeout(function() { hide_msg() }, minShowTime - showTime);
            return;
        }
        $popup_msg.hide();
    }
    window.popup_msg = popup_msg;
    window.hide_popup_msg = hide_msg;


    $(document).delegate('input.numeric', 'keyup', function(event){
        var num = this.value.replace(/[^0-9.+-]+|(.)[+-]/, '$1');

        if (this.value != num) {
            this.value = num;
        }

        $(this).tooltip('show');
    }).delegate('input.numeric:not(.notip)', 'focus', function(){
        var $t = $(this);

        if ($t.data('num_tip')) {
            return;
        }

        $t.data('num_tip', 1);

        $t.tooltip({
            title : function() {
                return fnum(this.value || 0);
            },
            animation : false
        }).tooltip('show');
    });
    
    $(document).delegate('form.ajax', 'submit', function(event){
        event.preventDefault();

        var base_version;
        if (/version=(\w+)/.test(location.search)) {
            if (!confirm('你当前提交不是基于最新版本的数据，是否继续？')) {
                return;
            }

            base_version = RegExp.$1;
        }

        popup_msg('数据保存中...', 'info');
        var $f = $(this);
        
        $f.trigger('before_submit');
        var $disabled = $f.find(':disabled[name]');
        $disabled.prop('disabled', false);
        var post_params = $f.serialize();
        $disabled.prop('disabled', true);

        if (!base_version) {
            base_version = 
                (($('#version-list a[href*="version="]:eq(1)').attr('href') || '')
                .match(/version=(\w+)/) || [] )[1];

            if (base_version) {
                post_params += '&base_version=' + base_version;
            }
        }

        $.post($f.attr('action') || location.href, post_params, function(ret){
            if (ret.code != 0) {
                if (ret.code == 3) {
                    popup_msg(ret ? ret.msg : '发生异常错误', 'info');
                } else {
                    popup_msg(ret ? ret.msg : '发生异常错误', 'error');
                }
            } else {

                $f.trigger('ajax_succ', ret); 

                if (ret.msg) {
                    popup_msg(ret.msg, 'succ');

                    if (/version=\w+/.test(location.search) && !ret.redirect_uri) {
                        return location.replace(location.href.replace(/version=\w+(&)?/, '').replace(/[&?]$/, ''));
                    }
                }
            }

            if (ret && ret.redirect_uri) {
                
                hide_popup_msg();
                if (/javascript\s*:\s*(.+)/.test(ret.redirect_uri)) {
                    $.globalEval(RegExp.$1);
                } else {
                    return location.replace(ret.redirect_uri);
                }
            }
            
            if (ret && ret.code == 0) {
                location.reload();
            }

        }, 'json').error(function(){
            popup_msg('服务器响应错误', 'error');
        });
    });

    //自动绑定日期控件
    $(document).delegate('input.datepicker', 'focus', function() {
        var $t = $(this);
        if ($t.data('datepicker')) {
            return;
        }
        $t.data('datepicker', 1);
        $t.datepicker({
            onSelect: function(){
            }
        });
    }).delegate('input.datetimepicker', 'focus', function(){
        var $t = $(this);

        if ($t.data('datetimepicker')) {
            return;
        }

        $t.data('datetimepicker', 1);
        $t.datetimepicker({
            timeFormat : 'HH',
            showMinute : false,
            showTime : false
        });
    });    

    $(document).delegate('select.filter', 'change', function(){
        $(this).closest('form').trigger('submit');
    });


    //单选、勾选框点击触发显示框架
    function bind_toggle_trigger() {
        $(':checkbox[rel^=trigger-],:radio[rel^=trigger-]').not('.trigger-toggle').click(function(event, from_trigger){
            var $t = $(this), type = $t.attr('rel').replace(/^trigger-/, ''),
            $targets = $('[rel~=target-' + type + ']');
            $untargets = $('[rel~=untarget-' + type + ']');

            if ($t.is(':radio') && ! from_trigger) {
                $(':radio[name=' + this.name + ']').not($t).each(function(){
                    $(this).triggerHandler('click', true);
                });
            }

            if ($t.is(':checked')) {
                $targets.show();
                $untargets.hide();
            } else {
                $targets.each(function(){
                    var $t = $(this); 
                    var all_unchecked = true;
                    $.each($t.attr('rel').split(/\s+/), function(i, target){
                        if (/target-(\S+)/.test(target)) {
                            if ($('[rel=trigger-' + RegExp.$1 + ']').prop('checked')) {
                                all_unchecked = false;
                                return false;
                            }
                        }
                    });
                    all_unchecked && $t.hide();
                });
                $untargets.show();
            }
        }).each(function(){ 
            $(this).addClass('trigger-toggle').triggerHandler('click');
        });
    }
    bind_toggle_trigger();
    $(window).bind('ajax_load_page', function(){
        bind_toggle_trigger();
    });

    $(function(){
        $(document).popover({
            selector : 'a[href*="material/edit?id"]',
            trigger : 'hover',
            title : '物料预览',
            html : true,
            delay : { show : 800, hide : 200 },
            content : function(){
                var id = $(this).attr('href').match(/id=(\d+)/)[1];

                return [
                    '<div style="width:200px;height:200px;text-align:center;line-height:200px;" class="muted">加载中...</div>',
                    '<iframe style="width:200px;height:200px;border:none;display:none" src="/material/preview?id=',
                    id, '" onload="$(this).prev().hide().end().show()" scrolling="no"></iframe>'
                ].join('');
            }
        });
    });

    $(document).delegate('table a.more', 'click', function(event){
        event.preventDefault();
        
        var $li = $(this).closest('li,tr');

        if ($li.next().is(':visible')) {
            $li.parent().find('li,tr').not($li).hide();
        } else {
            $li.parent().find('li,tr').not($li).show();
        }
    });

    $(document).delegate('[toggle]', 'click', function(event){
        event.preventDefault();

        var $t = $(this), $target = $($t.attr('toggle'));
        
        if ($target.is(':visible')) {
            $t.find('.icon-minus').removeClass('icon-minus').addClass('icon-plus');
            $target.hide();
        } else {
            $t.find('.icon-plus').removeClass('icon-plus').addClass('icon-minus');
            $target.show();
        }
    }).delegate(':checkbox.select-all', 'click', function(event){
        var $t = $(this), checked = $t.prop('checked'), $cnt = $t.closest('table');

        $cnt.find(':checkbox.select-item').prop('checked', checked);

    }).delegate(':checkbox.select-item', 'click', function(event){
        var $t = $(this), $cnt = $t.closest('table'), 
            all_checked = $cnt.find(':checkbox.select-item:not(:checked)').length == 0;

        $cnt.find(':checkbox.select-all').prop('checked', all_checked);
    });

    $(function(){
        $('[data-toggle=tooltip]').tooltip();
    });
})(); 

$.datepicker.setDefaults({
	monthNames : ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'],
	monthNamesShort : ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'],
	nextText : '下一月',
	prevText : '上一月',
	dayNames : ['日', '一', '二', '三', '四', '五', '六'],
	dayNamesShort : ['日', '一', '二', '三', '四', '五', '六'],
	dayNamesMin : ['日', '一', '二', '三', '四', '五', '六'],
	currentText : '今天',
	closeText : '完成',
	firstDay :  1,
	dateFormat : 'yy-mm-dd',
	numberOfMonths: 2,
    showOtherMonths: true,
	selectOtherMonths: false,
	showAnim : 'slideDown'
});

function fnum(num)
{
     num = (Math.round(num * 100) / 100) + ''; 
     return num.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function load_partial(content_id)
{
    var url = location.href;

    url += (url.indexOf('?') > 0 ? '&' : '?') + 'r=' + (+ new Date);

    popup_msg('数据加载中...', 'info');

    $.ajax({
        url: url,
        beforeSend: function(jqXHR, settings) {
            jqXHR.setRequestHeader("Partial", content_id);
        },  
        success: function(result) {
            $('[content-id=' + content_id + ']').html(result);
            hide_popup_msg();
        }   
    });  
}

function remove_list_item_val($input, item)
{
    var items = [];
   
    $.each($input.val().split(','), function(i, val) {
        if (val != item) {
            items.push(val);
        }
    });

    $input.val(items.join(','));
}
