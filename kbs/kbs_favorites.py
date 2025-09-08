from aiogram import types

kb_favorites_main = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Прочитано', callback_data = 'fav_read'),
            types.InlineKeyboardButton(text='Не прочитано', callback_data = 'fav_unread')
        ],
        [
            types.InlineKeyboardButton(text='Все избранное', callback_data = 'fav_all'),
            types.InlineKeyboardButton(text='В меню', callback_data = 'cancel')
        ]
    ]
)

kb_favorites_nav = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Назад', callback_data = 'fav_prev'),
            types.InlineKeyboardButton(text='Вперед', callback_data = 'fav_next')
        ],
        [
            types.InlineKeyboardButton(text='Прочитано', callback_data = 'fav_mark_read'),
            types.InlineKeyboardButton(text='Удалить', callback_data = 'fav_remove')
        ],
        [
            types.InlineKeyboardButton(text='К избранному', callback_data = 'fav_back_to_list')
        ]
    ]
)


kb_favorites_nav_read = types.InlineKeyboardMarkup(
    inline_keyboard = [
        [
            types.InlineKeyboardButton(text='Назад', callback_data = 'fav_prev'),
            types.InlineKeyboardButton(text='Вперед', callback_data = 'fav_next')
        ],
        [
            types.InlineKeyboardButton(text='Не прочитано', callback_data = 'fav_mark_unread'),
            types.InlineKeyboardButton(text='Удалить', callback_data = 'fav_remove')
        ],
        [
            types.InlineKeyboardButton(text='К избранному', callback_data = 'fav_back_to_list')
        ]
    ]
)
