from aiogram import types
from aiogram import F
from db.database import (
    get_favorites, remove_from_favorites, mark_as_read, mark_as_unread,
    save_number, get_number
)
from kbs.kbs_favorites import kb_favorites_main, kb_favorites_nav, kb_favorites_nav_read
from kbs.kbs_user import kb_nazad


async def show_favorites_menu(callback: types.CallbackQuery):
    """Показать главное меню избранного"""
    user_id = callback.from_user.id
    
    all_favorites = get_favorites(user_id)
    read_count = len(get_favorites(user_id, is_read=1))
    unread_count = len(get_favorites(user_id, is_read=0))
    
    if not all_favorites:
        text = "Ваше избранное пока что пустует..."
        try:
            await callback.message.edit_text(text, reply_markup=kb_nazad)
        except:
            pass
        await callback.answer()
        return
    
    text = f"Ваше избранное:\n\n"
    text += f"Всего книг: {len(all_favorites)}\n"
    text += f"Прочитано: {read_count}\n"
    text += f"Не прочитано: {unread_count}\n\n"
    text += "Выберите категорию для просмотра, человек."
    
    try:
        await callback.message.edit_text(text, reply_markup=kb_favorites_main)
    except:
        pass
    await callback.answer()


async def show_favorites_list(callback: types.CallbackQuery):
    """Показать список избранных книг с навигацией"""
    user_id = callback.from_user.id
    
    filter_map = {
        'fav_all': None,
        'fav_read': 1,
        'fav_unread': 0
    }
    
    is_read_filter = filter_map[callback.data]
    favorites = get_favorites(user_id, is_read=is_read_filter)
    
    if not favorites:
        category_names = {
            'fav_all': 'избранных',
            'fav_read': 'прочитанных',
            'fav_unread': 'непрочитанных'
        }
        text = f"У вас нет {category_names[callback.data]} книг."
        try:
            await callback.message.edit_text(text, reply_markup=kb_favorites_main)
        except:
            pass
        await callback.answer()
        return
    
    filter_name = callback.data
    save_number(user_id, f'favorites_{filter_name}', 0)
    save_number(user_id, 'current_favorites_filter', {'fav_all': 0, 'fav_read': 1, 'fav_unread': 2}[filter_name])
    
    await show_favorite_book(callback, filter_name, 0)


async def show_favorite_book(callback: types.CallbackQuery, filter_name: str, index: int):
    """Показать конкретную книгу из избранного"""
    user_id = callback.from_user.id
    
    filter_map = {
        'fav_all': None,
        'fav_read': 1, 
        'fav_unread': 0
    }
    
    is_read_filter = filter_map[filter_name]
    favorites = get_favorites(user_id, is_read=is_read_filter)
    
    if not favorites:
        await show_favorites_menu(callback)
        return
    
    if index < 0:
        index = 0
    if index >= len(favorites):
        index = len(favorites) - 1
    
    save_number(user_id, f'favorites_{filter_name}', index)
    
    book = favorites[index]
    
    text = f"Избранное ({index + 1}/{len(favorites)})\n\n"
    text += f"{book[0]}\n"  # book_name
    text += f"{book[1]}\n\n"  # book_author
    text += f"{book[2]}\n\n"  # book_description
    
    if book[3] == 1:  # is_read
        text += "Прочитано"
        keyboard = kb_favorites_nav_read
    else:
        text += "Не прочитано"
        keyboard = kb_favorites_nav
    
    try:
        await callback.message.edit_text(text, reply_markup=keyboard)
    except:
        pass
    await callback.answer()


async def navigate_favorites(callback: types.CallbackQuery):
    """Навигация по избранным книгам (вперед/назад)"""
    user_id = callback.from_user.id
    
    current_filter = None
    current_index = 0
    
  
    filter_code = get_number(user_id, 'current_favorites_filter')
    filter_names = ['fav_all', 'fav_read', 'fav_unread']
    
    if 0 <= filter_code < len(filter_names):
        current_filter = filter_names[filter_code]
        current_index = get_number(user_id, f'favorites_{current_filter}')
    else:
        current_filter = 'fav_all'
        current_index = 0
    
    if current_filter is None:
        await callback.answer("Ошибка навигации. Попробуйте заново.")
        return
    
    if callback.data == 'fav_next':
        new_index = current_index + 1
    elif callback.data == 'fav_prev':
        new_index = current_index - 1
    else:
        await callback.answer("Неизвестная команда навигации.")
        return
    
    filter_map = {
        'fav_all': None,
        'fav_read': 1,
        'fav_unread': 0
    }
    
    favorites = get_favorites(user_id, is_read=filter_map[current_filter])
    
    if new_index < 0:
        await callback.answer("Это Ваша первая книга в списке.")
        return
    if new_index >= len(favorites):
        await callback.answer("Вот и Ваша последняя книга в списке...")
        return
    
    await show_favorite_book(callback, current_filter, new_index)


async def manage_favorite_book(callback: types.CallbackQuery):
    """Управление книгой: отметить прочитанной/непрочитанной, удалить"""
    user_id = callback.from_user.id
    
    current_filter = None
    current_index = 0
    
    filter_code = get_number(user_id, 'current_favorites_filter')
    filter_names = ['fav_all', 'fav_read', 'fav_unread']
    
    if 0 <= filter_code < len(filter_names):
        current_filter = filter_names[filter_code]
        current_index = get_number(user_id, f'favorites_{current_filter}')
    else:
        # Если нет сохранённого фильтра, по умолчанию "все"
        current_filter = 'fav_all'
        current_index = 0
    
    if current_filter is None:
        await callback.answer("Ошибка. Попробуйте заново.")
        return
    
    filter_map = {
        'fav_all': None,
        'fav_read': 1,
        'fav_unread': 0
    }
    
    favorites = get_favorites(user_id, is_read=filter_map[current_filter])
    
    if not favorites or current_index >= len(favorites):
        await show_favorites_menu(callback)
        return
    
    book = favorites[current_index]
    book_name = book[0]  # book_name
    book_author = book[1]  # book_author
    
    if callback.data == 'fav_mark_read':
        mark_as_read(user_id, book_name, book_author)
        await callback.answer("Отмечу книгу как прочитанную.")
        
    elif callback.data == 'fav_mark_unread':
        mark_as_unread(user_id, book_name, book_author)
        await callback.answer("Отмечу книгу как непрочитанную.")
        
    elif callback.data == 'fav_remove':
        remove_from_favorites(user_id, book_name, book_author)
        await callback.answer("Удалил книгу из избранного.")
        
        updated_favorites = get_favorites(user_id, is_read=filter_map[current_filter])
        if not updated_favorites:
            await show_favorites_menu(callback)
            return
        
        if current_index >= len(updated_favorites):
            current_index = len(updated_favorites) - 1
            
        await show_favorite_book(callback, current_filter, current_index)
        return
    
    elif callback.data == 'fav_back_to_list':
        await show_favorites_menu(callback)
        return
    
    updated_favorites = get_favorites(user_id, is_read=filter_map[current_filter])
    if updated_favorites and current_index < len(updated_favorites):
        await show_favorite_book(callback, current_filter, current_index)
    else:
        await show_favorites_menu(callback)


def register_favorites_handlers(dp):
    """Регистрация обработчиков для избранного"""
    dp.callback_query(F.data == 'favorites')(show_favorites_menu)
    dp.callback_query(F.data.in_(['fav_all', 'fav_read', 'fav_unread']))(show_favorites_list)
    dp.callback_query(F.data.in_(['fav_next', 'fav_prev']))(navigate_favorites)
    dp.callback_query(F.data.in_(['fav_mark_read', 'fav_mark_unread', 'fav_remove', 'fav_back_to_list']))(manage_favorite_book)
